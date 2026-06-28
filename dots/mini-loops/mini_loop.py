#!/usr/bin/env python3
"""mini_loop.py - shared runner for the mini-loops framework.

A "mini-loop" is an autonomous life routine: gather items from a source, ground
them against what the user is CURRENTLY working on (active projects), judge which
have a concrete consequence for one of those projects, and act (a terse Telegram
ping + a full KB note). Each loop is a small spec; this one runner executes any.

Invocation:  mini_loop.py <loop-name>
The loop spec is read from $MINI_LOOP_SPEC (a JSON file the nix module generates
per loop). Spec shape (see modules/services/mini-loops.nix):

  {
    "name": "x-life-scan",
    "gather": "x-feed-scan",        # shell command; stdout = gathered items (text)
    "seeds": ["my projects ...", "local AI ...", ...],
    "judge": "<the consequence-judging prompt>",
    "telegram": true,
    "kb": true
  }

Steps:
  a. gather  - run spec.gather, capture stdout as the raw items text.
  b. ground  - build an "ACTIVE PROJECTS" block: what Hari is currently working
               on (GitHub public repos sorted by push + local git repos with a
               recent commit). Falls back to kb-search of the static seeds if both
               project sources fail.
  c. judge   - POST items + context + judge prompt to the local brain; parse a
               JSON list of {item, relevant, why, headline, project}. Robust to
               chatter/fences and bare {...} object streams.
  d. act     - terse Telegram (top 3 relevant items, one project-anchored
               sentence each; silence if nothing connects) and/or a KB note that
               keeps the full record (every surfaced item + its why).
  e. log     - one line to runlog.log (OK/FAIL/SKIP) + a per-run detail JSON.

Everything is loopback-only (brain at 127.0.0.1:18080). Telegram uses the Bot
API with the token+allowlist from /run/secrets/hermes-telegram.env. Failures
degrade to SKIP/FAIL with a logged note rather than crashing the timer.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

STATE_DIR = os.environ.get("MINI_LOOPS_DIR", "/var/lib/mini-loops")
RUNS_DIR = os.path.join(STATE_DIR, "runs")
RUNLOG = os.path.join(STATE_DIR, "runlog.log")
KB_LOOPS_DIR = os.environ.get("MINI_LOOPS_KB_DIR", "/var/lib/kb/staging/loops")

BRAIN_URL = os.environ.get(
    "MINI_LOOP_BRAIN_URL", "http://127.0.0.1:18080/v1/chat/completions"
)
BRAIN_MODEL = os.environ.get("MINI_LOOP_BRAIN_MODEL", "qwen3.6-35b-a3b")
TELEGRAM_ENV = os.environ.get(
    "MINI_LOOP_TELEGRAM_ENV", "/run/secrets/hermes-telegram.env"
)

# Active-projects grounding: the two signals for "what Hari is working on now".
GITHUB_USER = os.environ.get("MINI_LOOP_GITHUB_USER", "harivansh-afk")
LOCAL_GIT_DIR = os.environ.get("MINI_LOOP_LOCAL_GIT_DIR", "/home/rathi/Documents/Git")
# Local repos count as "active" if they have a commit within this window.
LOCAL_GIT_DAYS = int(os.environ.get("MINI_LOOP_LOCAL_GIT_DAYS", "21") or "21")
# Cap the combined active-projects list so the judge prompt stays compact.
ACTIVE_PROJECTS_CAP = int(os.environ.get("MINI_LOOP_ACTIVE_PROJECTS_CAP", "15") or "15")
# At most this many surfaced items go to Telegram (one sentence each).
TELEGRAM_MAX_ITEMS = int(os.environ.get("MINI_LOOP_TELEGRAM_MAX", "3") or "3")


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _log_line(name: str, status: str, note: str) -> None:
    """Append one human-readable line to runlog.log."""
    line = f"{_now_iso()}  {name}  {status}  {note}\n"
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        with open(RUNLOG, "a", encoding="utf-8") as fh:
            fh.write(line)
    except Exception:
        pass
    # Also echo to stdout so `journalctl -u mini-loop-<name>` shows it.
    sys.stdout.write(line)


def _write_run_detail(name: str, detail: dict) -> None:
    out = os.path.join(RUNS_DIR, name)
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, _now_iso() + ".json")
    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(detail, fh, indent=2)
    except Exception:
        pass


# --- a. gather ---------------------------------------------------------------
def gather(cmd: str) -> str:
    """Run the loop's gather command; return its stdout (the items text)."""
    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=900,
        )
    except subprocess.TimeoutExpired:
        return ""
    return (proc.stdout or "").strip()


# --- b. ground ---------------------------------------------------------------
def _github_active_projects() -> list[dict]:
    """Hari's public GitHub repos, most-recently-pushed first (no token needed).

    Returns [{name, desc, language, pushed}], or [] on any error/rate-limit so
    the caller can fall back. This is the primary "currently looking at" signal.
    """
    url = (
        f"https://api.github.com/users/{GITHUB_USER}/repos"
        "?sort=pushed&per_page=15"
    )
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "mini-loops",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.load(resp)
    except Exception as exc:
        print(f"mini_loop: github repos fetch failed: {exc}", file=sys.stderr)
        return []
    if not isinstance(data, list):
        return []
    out = []
    for repo in data:
        if not isinstance(repo, dict) or repo.get("fork"):
            continue
        name = str(repo.get("name", "")).strip()
        if not name:
            continue
        out.append(
            {
                "name": name,
                "desc": (repo.get("description") or "").strip(),
                "language": (repo.get("language") or "").strip(),
                "pushed": (repo.get("pushed_at") or "").strip(),
            }
        )
    return out


def _local_active_projects() -> list[dict]:
    """Local git repos under LOCAL_GIT_DIR with a commit in the last N days.

    Returns [{name, desc}] where desc is the latest commit subject. Errors per
    repo are skipped quietly.
    """
    out = []
    try:
        entries = sorted(os.listdir(LOCAL_GIT_DIR))
    except Exception:
        return []
    since = f"{LOCAL_GIT_DAYS} days ago"
    for entry in entries:
        repo = os.path.join(LOCAL_GIT_DIR, entry)
        if not os.path.isdir(os.path.join(repo, ".git")):
            continue
        try:
            proc = subprocess.run(
                ["git", "-C", repo, "log", "-1", f"--since={since}", "--format=%s"],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except Exception:
            continue
        subject = (proc.stdout or "").strip().splitlines()
        if not subject:
            continue  # no commit within the window -> not active
        out.append({"name": entry, "desc": subject[0][:120]})
    return out


def _format_active_projects(projects: list[dict]) -> str:
    """Render the deduped active-projects list as a compact context block."""
    lines = []
    for p in projects:
        bits = [p["name"]]
        if p.get("language"):
            bits.append(f"[{p['language']}]")
        if p.get("desc"):
            bits.append(f"- {p['desc']}")
        line = " ".join(bits)
        if p.get("pushed"):
            line += f" (pushed {p['pushed'][:10]})"
        lines.append("- " + line)
    return "ACTIVE PROJECTS (what Hari is working on now):\n" + "\n".join(lines)


def active_projects() -> str:
    """Build the ACTIVE PROJECTS grounding block (GitHub + local git, deduped)."""
    gh = _github_active_projects()
    local = _local_active_projects()
    merged: dict[str, dict] = {}
    # GitHub first (richer metadata), then fill in local-only repos.
    for p in gh + local:
        key = p["name"].lower()
        if key in merged:
            # Prefer a non-empty desc if the existing entry lacks one.
            if not merged[key].get("desc") and p.get("desc"):
                merged[key]["desc"] = p["desc"]
            continue
        merged[key] = dict(p)
    projects = list(merged.values())[:ACTIVE_PROJECTS_CAP]
    if not projects:
        return ""
    return _format_active_projects(projects)


def ground(seeds: list[str]) -> str:
    """kb-search each seed; build a compact 'about Hari' context block.

    This is the FALLBACK grounding, used only when the active-projects signal is
    unavailable (both GitHub and local git failed)."""
    blocks = []
    for seed in seeds:
        try:
            proc = subprocess.run(
                ["kb-search", seed],
                capture_output=True,
                text=True,
                timeout=120,
            )
            hits = (proc.stdout or "").strip()
        except Exception:
            hits = ""
        if hits:
            blocks.append(f"## seed: {seed}\n{hits}")
    if not blocks:
        return "(no personal context found)"
    return "\n\n".join(blocks)


# --- c. judge ----------------------------------------------------------------
def _extract_json_array(text: str):
    """Pull a JSON array of objects out of a possibly-chatty model reply."""
    text = text.strip()
    # Strip ```json ... ``` fences if present.
    fence = re.search(r"```(?:json)?\s*(.+?)```", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    # Direct parse first.
    try:
        val = json.loads(text)
        if isinstance(val, list):
            return val
        if isinstance(val, dict):
            for v in val.values():
                if isinstance(v, list):
                    return v
    except Exception:
        pass
    # Fallback: grab the first [...] span.
    start = text.find("[")
    end = text.rfind("]")
    if start != -1 and end != -1 and end > start:
        try:
            val = json.loads(text[start : end + 1])
            if isinstance(val, list):
                return val
        except Exception:
            pass
    # Last resort: the model often emits a BARE STREAM of objects with no array
    # brackets or commas ("{...}\n{...}\n..."). Brace-match each top-level {...}
    # and json.loads it individually. This also recovers objects from inside a
    # malformed array.
    objs = []
    depth = 0
    obj_start = None
    in_str = False
    esc = False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            if depth == 0:
                obj_start = i
            depth += 1
        elif ch == "}":
            if depth > 0:
                depth -= 1
                if depth == 0 and obj_start is not None:
                    try:
                        o = json.loads(text[obj_start : i + 1])
                        if isinstance(o, dict):
                            objs.append(o)
                    except Exception:
                        pass
                    obj_start = None
    return objs


def judge(items: str, context: str, judge_prompt: str) -> list[dict]:
    """Ask the local brain which items concretely matter for an active project."""
    system = (
        judge_prompt
        + "\n\nYou are given (1) a CONTEXT block listing the projects Hari is "
        "ACTIVELY working on right now and (2) a list of ITEMS. Mark an item "
        "relevant=true ONLY if it has a concrete, specific consequence for one of "
        "those active projects, and the connection genuinely makes sense - no "
        "stretchy or generic links. When in doubt, mark it relevant=false. "
        "Respond with ONLY a JSON array, one object per item you considered, each: "
        '{"item": "<short identifier or the item text/url>", "relevant": '
        'true|false, "project": "<the active project it ties to, or empty>", '
        '"headline": "<for relevant items: ONE concise sentence, anchored to the '
        'project, suitable to send as-is; empty otherwise>", "why": "<one '
        "sentence: the concrete connection, or why it is noise>\"}. Surface only "
        "items with a real consequence for an active project; skip generic noise."
    )
    user = f"CONTEXT (Hari's active projects):\n{context}\n\nITEMS:\n{items}"
    payload = {
        "model": BRAIN_MODEL,
        "temperature": 0.3,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        BRAIN_URL, body, {"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.load(resp)
        content = data["choices"][0]["message"]["content"]
    except Exception as exc:
        print(f"mini_loop: brain unreachable: {exc}", file=sys.stderr)
        return []
    parsed = _extract_json_array(content)
    out = []
    for entry in parsed:
        if not isinstance(entry, dict):
            continue
        out.append(
            {
                "item": str(entry.get("item", "")).strip(),
                "relevant": bool(entry.get("relevant", False)),
                "project": str(entry.get("project", "")).strip(),
                "headline": str(entry.get("headline", "")).strip(),
                "why": str(entry.get("why", "")).strip(),
            }
        )
    return out


# --- d. act ------------------------------------------------------------------
def _telegram_config() -> tuple[str | None, list[str]]:
    """Parse TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS from the sops env file."""
    token = None
    users: list[str] = []
    try:
        with open(TELEGRAM_ENV, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                val = val.strip().strip('"').strip("'")
                if key.strip() == "TELEGRAM_BOT_TOKEN":
                    token = val
                elif key.strip() == "TELEGRAM_ALLOWED_USERS":
                    users = [u.strip() for u in val.replace(";", ",").split(",") if u.strip()]
    except Exception:
        return None, []
    return token, users


def _telegram_line(s: dict) -> str:
    """One terse, project-anchored sentence for a surfaced item.

    Prefer the judge's `headline` (already one project-anchored sentence). Fall
    back to "<project>: <why>" / the why alone if the headline is missing."""
    headline = s.get("headline", "").strip()
    if headline:
        return headline
    why = s.get("why", "").strip()
    project = s.get("project", "").strip()
    if project and why:
        return f"{project}: {why}"
    return why or s.get("item", "").strip()


def send_telegram(name: str, surfaced: list[dict]) -> bool:
    """Send the top few project-anchored items, one sentence each.

    Returns True if a message was actually sent. Stays SILENT (sends nothing,
    returns False) when nothing connects to an active project - silence is fine.
    """
    token, users = _telegram_config()
    if not token or not users:
        print("mini_loop: no telegram token/allowlist; skipping telegram", file=sys.stderr)
        return False
    top = surfaced[:TELEGRAM_MAX_ITEMS]
    sentences = [ln for ln in (_telegram_line(s) for s in top) if ln]
    if not sentences:
        return False
    text = "\n".join(f"- {ln}" for ln in sentences)
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    sent = False
    for chat_id in users:
        payload = json.dumps({"chat_id": chat_id, "text": text, "disable_web_page_preview": False}).encode()
        req = urllib.request.Request(url, payload, {"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=30).read()
            sent = True
        except Exception as exc:
            print(f"mini_loop: telegram send failed for {chat_id}: {exc}", file=sys.stderr)
    return sent


def write_kb_note(name: str, surfaced: list[dict]) -> None:
    out = os.path.join(KB_LOOPS_DIR, name)
    os.makedirs(out, exist_ok=True)
    runts = _now_iso()
    path = os.path.join(out, runts + ".md")
    try:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("---\n")
            fh.write(f"loop: {name}\n")
            fh.write(f"run: {runts}\n")
            fh.write(f"surfaced: {len(surfaced)}\n")
            fh.write("tags: mini-loops, " + name + "\n")
            fh.write("---\n\n")
            fh.write(f"# {name} - surfaced ({runts})\n\n")
            for s in surfaced:
                fh.write(f"## {s['item']}\n\n")
                if s.get("project"):
                    fh.write(f"Project: {s['project']}\n\n")
                if s.get("headline"):
                    fh.write(f"Headline: {s['headline']}\n\n")
                fh.write(f"Why: {s['why']}\n\n")
    except Exception as exc:
        print(f"mini_loop: kb note write failed: {exc}", file=sys.stderr)


# --- main --------------------------------------------------------------------
def main() -> int:
    if len(sys.argv) < 2:
        print("usage: mini_loop.py <loop-name>", file=sys.stderr)
        return 2
    name = sys.argv[1]

    spec_path = os.environ.get("MINI_LOOP_SPEC")
    if not spec_path or not os.path.exists(spec_path):
        _log_line(name, "FAIL", "no spec file")
        return 1
    try:
        with open(spec_path, encoding="utf-8") as fh:
            spec = json.load(fh)
    except Exception as exc:
        _log_line(name, "FAIL", f"bad spec: {exc}")
        return 1

    t0 = time.monotonic()

    items = gather(spec.get("gather", ""))
    if not items:
        _log_line(name, "SKIP", "no items gathered")
        return 0

    n_gathered = len([ln for ln in items.splitlines() if ln.strip()])

    # Ground against what Hari is working on NOW; fall back to the kb-search
    # seeds only if both project signals are unavailable.
    context = active_projects()
    grounding = "active-projects"
    if not context:
        context = ground(spec.get("seeds", []))
        grounding = "seeds-fallback"

    judged = judge(items, context, spec.get("judge", ""))
    if not judged:
        dur = time.monotonic() - t0
        _write_run_detail(
            name,
            {"run": _now_iso(), "grounding": grounding, "context": context,
             "gathered": items, "judged": [], "surfaced": []},
        )
        _log_line(name, "FAIL", f"gathered={n_gathered} judge returned nothing dur={dur:.1f}s")
        return 1

    surfaced = [j for j in judged if j.get("relevant")]

    sent = False
    if surfaced:
        # KB keeps the full record; Telegram stays terse (and silent if nothing
        # ties to an active project).
        if spec.get("kb"):
            write_kb_note(name, surfaced)
        if spec.get("telegram"):
            sent = send_telegram(name, surfaced)

    _write_run_detail(
        name,
        {
            "run": _now_iso(),
            "grounding": grounding,
            "context": context,
            "gathered": items,
            "judged": judged,
            "surfaced": surfaced,
        },
    )

    dur = time.monotonic() - t0
    tg = "tg=sent" if sent else "tg=silent"
    _log_line(
        name,
        "OK",
        f"gathered={n_gathered} surfaced={len(surfaced)} {tg} ground={grounding} dur={dur:.1f}s",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
