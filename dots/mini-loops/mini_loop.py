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
    "gate": "active-project",       # or "anomaly" (finance); default active-project
    "telegram": true,
    "kb": true
  }

Steps:
  a. gather  - run spec.gather, capture stdout as the raw items text.
  b. ground  - build an "ACTIVE PROJECTS" block: what Hari is currently working
               on (GitHub public repos sorted by push + local git repos with a
               recent commit). Falls back to kb-search of the static seeds if both
               project sources fail.
  c. gate    - a TWO-STAGE interestingness gate (precision over recall; few,
               excellent pings). Stage A scores each item on 5 independent boolean
               signals via the brain; an item survives only if it clears the
               threshold (>= MINI_LOOP_MIN_SIGNALS, and - for the active-project
               gate - the project-tie signal is required). Stage B is an
               adversarial skeptic brain call that defaults to DROP and keeps only
               genuinely notable survivors. The gate is loop-aware: "active-project"
               (x/hn/dep loops) requires a concrete tie to a current project;
               "anomaly" (finance) keys on "real, novel money anomaly" instead.
  d. act     - terse Telegram (top 3 surviving items, one anchored sentence each,
               each line carrying provenance: a "[<loop>]" label + the source ref
               (a URL for x/hn/dep, merchant+date for finance which has no URL);
               silence if nothing survives the gate) and/or a KB note that keeps
               the full record (every surfaced item + its signals + why).
  e. log     - one line to runlog.log (OK/FAIL/SKIP) + a per-run detail JSON
               (includes the per-item signal scores so the gate is inspectable).

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
# Stage-A gate: minimum number of the 5 signals an item must score to survive.
# The bar is HIGH on purpose (precision over recall). For the active-project gate
# the project-tie signal is ALSO required regardless of this count.
# Active-project gate threshold: the project-tie signal is required (see
# _passes_stage_a) PLUS this many total signals. 3 = project-tie + 2 quality
# signals, then the adversarial skeptic does final pruning. 4 was too strict
# (surfaced nothing); the skeptic is the real precision guard, not this count.
MIN_SIGNALS = int(os.environ.get("MINI_LOOP_MIN_SIGNALS", "3") or "3")


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


def _brain_call(system: str, user: str, temperature: float = 0.2) -> str:
    """POST one chat completion to the local brain; return content or '' on error."""
    payload = {
        "model": BRAIN_MODEL,
        "temperature": temperature,
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
        return data["choices"][0]["message"]["content"]
    except Exception as exc:
        print(f"mini_loop: brain unreachable: {exc}", file=sys.stderr)
        return ""


# The five independent signals scored in Stage A. SIG_PROJECT is index 0 and is
# REQUIRED for the active-project gate (an item with no concrete project tie is
# dropped no matter how it scores elsewhere).
_SIGNAL_KEYS = ["s_project", "s_novel", "s_actionable", "s_magnitude", "s_rare"]


def _signal_count(entry: dict) -> int:
    return sum(1 for k in _SIGNAL_KEYS if bool(entry.get(k)))


def judge_signals(
    items: str, context: str, judge_prompt: str, gate: str
) -> list[dict]:
    """Stage A - score each gathered item on 5 independent boolean signals.

    The brain rates, per item: (1) ties to a CURRENTLY-ACTIVE project, (2) novel /
    non-obvious, (3) actionable / decision-relevant, (4) notable magnitude (a major
    launch/release/finding, not incremental), (5) rare (does not show up often).
    Returns one dict per item with the five booleans plus project/headline/why.
    The keep decision is made by the caller (gate-aware threshold)."""
    if gate == "anomaly":
        signal_doc = (
            "Score these five INDEPENDENT booleans for each item (an item here is a "
            "candidate money anomaly already computed deterministically):\n"
            '  "s_project": this anomaly clearly concerns Hari\'s own money/accounts '
            "(true for every real anomaly; reserve false only for obvious parsing "
            "junk),\n"
            '  "s_novel": this is new information, not something already obvious or '
            "previously flagged,\n"
            '  "s_actionable": Hari could act on it (cancel a sub, dispute a charge, '
            "investigate),\n"
            '  "s_magnitude": the dollar impact is meaningful, not trivial,\n'
            '  "s_rare": this is an unusual event, not normal recurring spend.\n'
        )
        anchor = "the account/merchant"
    else:
        signal_doc = (
            "Score these five INDEPENDENT booleans for each item:\n"
            '  "s_project": it has a concrete, specific tie to a CURRENTLY-ACTIVE '
            "project in the CONTEXT (no stretchy or generic links),\n"
            '  "s_novel": it is novel / non-obvious, not common knowledge,\n'
            '  "s_actionable": it is actionable / decision-relevant for that '
            "project,\n"
            '  "s_magnitude": it is notable magnitude - a major launch, release, or '
            "finding, NOT an incremental update,\n"
            '  "s_rare": it is rare - the kind of thing that does not show up often.\n'
        )
        anchor = "the active project"
    system = (
        judge_prompt
        + "\n\nYou are the first stage of a HIGH-BAR interestingness gate that "
        "protects Hari's attention: precision over recall, few excellent items. "
        "You are given (1) a CONTEXT block and (2) a list of ITEMS. For EACH item "
        "score five booleans honestly - do not inflate them. " + signal_doc
        + "Respond with ONLY a JSON array, one object per item you considered, each:"
        ' {"item": "<short identifier or the item text/url>", '
        '"s_project": true|false, "s_novel": true|false, "s_actionable": '
        'true|false, "s_magnitude": true|false, "s_rare": true|false, '
        '"project": "<' + anchor + ' it ties to, or empty>", '
        '"headline": "<ONE concise sentence anchored to ' + anchor + ", suitable "
        'to send as-is>", "why": "<one sentence: the concrete reason it matters, '
        'or why it is noise>"}.'
    )
    user = f"CONTEXT:\n{context}\n\nITEMS:\n{items}"
    content = _brain_call(system, user, temperature=0.2)
    if not content:
        return []
    parsed = _extract_json_array(content)
    out = []
    for entry in parsed:
        if not isinstance(entry, dict):
            continue
        rec = {
            "item": str(entry.get("item", "")).strip(),
            "project": str(entry.get("project", "")).strip(),
            "headline": str(entry.get("headline", "")).strip(),
            "why": str(entry.get("why", "")).strip(),
        }
        for k in _SIGNAL_KEYS:
            rec[k] = bool(entry.get(k, False))
        rec["signals"] = _signal_count(rec)
        out.append(rec)
    return out


def _passes_stage_a(entry: dict, gate: str) -> bool:
    """Threshold check.

    Anomaly gate (finance): the deterministic scanner ALREADY did the filtering
    (it only emits real subscriptions / large / duplicate charges), so the 5
    feed-signals (novel/rare/project-tie/...) do not apply - a recurring sub is
    not "novel" or "project-tied". Pass everything through to the skeptic, which
    is the real finance filter. Re-scoring on feed-signals here wrongly dropped
    every subscription.

    Active-project gate (x/hn/dep): require the project-tie signal AND at least
    MIN_SIGNALS total."""
    if gate == "anomaly":
        return True
    if not entry.get("s_project"):
        return False
    return entry.get("signals", 0) >= MIN_SIGNALS


def skeptic_filter(
    survivors: list[dict], context: str, gate: str
) -> list[dict]:
    """Stage B - one adversarial brain call that tries to REJECT the survivors.

    Defaults to DROP; keeps an item only if it is genuinely notable. Returns the
    kept subset (matched back to the Stage-A records by item identifier)."""
    if not survivors:
        return []
    if gate == "anomaly":
        mission = (
            "You are a skeptic protecting Hari's attention about his money. Default "
            "to DROP. Keep a candidate ONLY if it is a REAL, novel money anomaly "
            "genuinely worth interrupting him for (a new recurring subscription, a "
            "real price hike, an unusually large or duplicate charge). Reject "
            "anything that is normal spending, trivially small, ambiguous, or "
            "likely a parsing artifact."
        )
    else:
        mission = (
            "You are a skeptic protecting Hari's attention. Default to DROP. Keep an "
            "item ONLY if it is genuinely notable AND concretely tied to an active "
            "project he is working on right now. Reject anything generic, "
            "incremental, or a stretch."
        )
    candidates = "\n".join(
        f'{i}. item="{s.get("item", "")}" project="{s.get("project", "")}" '
        f'headline="{s.get("headline", "")}" why="{s.get("why", "")}"'
        for i, s in enumerate(survivors)
    )
    system = (
        mission
        + " You are given the CONTEXT and a numbered list of CANDIDATES that passed "
        "a first filter. Respond with ONLY a JSON array of the integer indices you "
        'KEEP (e.g. [0, 2]); return [] to keep none. Be ruthless: when in doubt, '
        "drop it."
    )
    user = f"CONTEXT:\n{context}\n\nCANDIDATES:\n{candidates}"
    content = _brain_call(system, user, temperature=0.0)
    if not content:
        # If the skeptic is unreachable, fail CLOSED: surface nothing rather than
        # ping on items that never cleared the second stage.
        print("mini_loop: skeptic unreachable; dropping all (fail closed)", file=sys.stderr)
        return []
    parsed = _extract_json_array(content)
    keep_idx: set[int] = set()
    for v in parsed:
        try:
            keep_idx.add(int(v))
        except (TypeError, ValueError):
            continue
    return [s for i, s in enumerate(survivors) if i in keep_idx]


def gate_items(
    items: str, context: str, judge_prompt: str, gate: str
) -> tuple[list[dict], list[dict]]:
    """Run the full two-stage gate. Returns (all_scored, surfaced) where
    all_scored is every Stage-A record (for the inspectable run JSON) and surfaced
    is the Stage-B skeptic survivors.

    Anomaly gate (finance): the deterministic scanner already did the filtering
    (it emits ONLY real subscriptions / large / duplicate charges, excludes
    income/transfers/noise, and dedups via its own state so each is reported
    once). So surface its candidate lines DIRECTLY - no feed-signal scoring, no
    ruthless skeptic. The skeptic was dropping legitimate subscriptions (OpenAI,
    Claude, etc.) as "normal spending", which is exactly what Hari wants to see."""
    if gate == "anomaly":
        records = []
        for ln in items.splitlines():
            ln = ln.strip()
            if ln:
                records.append(
                    {"item": ln, "headline": ln, "project": "", "why": ln, "signals": 0}
                )
        return records, records
    scored = judge_signals(items, context, judge_prompt, gate)
    stage_a = [e for e in scored if _passes_stage_a(e, gate)]
    surfaced = skeptic_filter(stage_a, context, gate)
    return scored, surfaced


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


_URL_RE = re.compile(r"https?://\S+")
_DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")


def _source_ref(s: dict) -> str:
    """The item's source identifier, used as the "-> <source>" provenance suffix.

    Prefer a real URL (X post / HN / dep release): it lives in the surfaced
    record's `item` (the gather line is shaped like '... | <url> | ...') or
    sometimes the `headline`/`why`. URL wins because it is unambiguous.

    For URL-less items (finance anomalies have no URL) fall back to merchant+date:
    the gate keeps the original candidate text in `item` (e.g. "DUPLICATE CHARGE:
    Companion Inc charged 20.00 5 times on 2026-04-16"), which already names the
    merchant and carries a YYYY-MM-DD. Returning that as the source ref makes the
    finance provenance explicit even when the model's headline paraphrases it."""
    for field in ("item", "headline", "why"):
        m = _URL_RE.search(s.get(field, "") or "")
        if m:
            return m.group(0).rstrip(").,;|>\"'")
    # No URL: build a merchant+date ref from the original candidate text in `item`.
    item = (s.get("item", "") or "").strip()
    if not item:
        return ""
    # Strip the leading "KIND:" tag (SUBSCRIPTION/LARGE CHARGE/DUPLICATE CHARGE)
    # so the ref reads as "<merchant ...>, <date>".
    ref = re.sub(r"^[A-Z][A-Z ]+:\s*", "", item).strip()
    date = ""
    m = _DATE_RE.search(item)
    if m:
        date = m.group(0)
    # Keep the ref short: take up to the merchant + amount portion, append the date.
    ref = ref.split(" charged ")[0].split(" ~")[0].strip().rstrip(".,;")
    if date and date not in ref:
        ref = f"{ref}, {date}" if ref else date
    return ref


def _telegram_line(s: dict, loop_name: str) -> str:
    """One terse, provenance-carrying line for a surfaced item.

    Format: "[<loop>] <one-sentence headline> -> <source>". Prefer the judge's
    `headline`; fall back to "<project>: <why>" / the why alone. The loop label
    makes it unambiguous that the line is a surfacing from <loop>, and the source
    ref (URL for x/hn/dep, merchant+date for finance) makes provenance explicit so
    the assistant never confabulates where a ping came from."""
    headline = s.get("headline", "").strip()
    if headline:
        body = headline
    else:
        why = s.get("why", "").strip()
        project = s.get("project", "").strip()
        body = f"{project}: {why}" if (project and why) else (why or s.get("item", "").strip())
    if not body:
        return ""
    line = f"[{loop_name}] {body}"
    ref = _source_ref(s)
    # Avoid a duplicate suffix if the body already contains it.
    if ref and ref not in line:
        line += f" -> {ref}"
    return line


def send_telegram(name: str, surfaced: list[dict], gate: str = "active-project") -> bool:
    """Send the surfaced items, one sentence each.

    Returns True if a message was actually sent. Stays SILENT (sends nothing,
    returns False) when nothing survived the gate - silence is fine.

    Feed loops (active-project) cap at TELEGRAM_MAX_ITEMS to stay terse. The
    anomaly (finance) loop sends ALL surfaced items: the scanner dedups via its
    own state, so this is a one-time subscription/anomaly digest on first run,
    then only newly-detected items - capping it would hide subs Hari wants."""
    token, users = _telegram_config()
    if not token or not users:
        print("mini_loop: no telegram token/allowlist; skipping telegram", file=sys.stderr)
        return False
    top = surfaced if gate == "anomaly" else surfaced[:TELEGRAM_MAX_ITEMS]
    sentences = [ln for ln in (_telegram_line(s, name) for s in top) if ln]
    if not sentences:
        return False
    text = "\n".join(f"- {ln}" for ln in sentences)
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    sent = False
    for chat_id in users:
        payload = json.dumps({"chat_id": chat_id, "text": text, "disable_web_page_preview": False}).encode()
        # Retry once on a transient error: two loops can fire near-simultaneously
        # and a send can time out, which would log a false "silent". A genuinely
        # surfaced item must reliably ping.
        for attempt in range(2):
            req = urllib.request.Request(url, payload, {"Content-Type": "application/json"})
            try:
                urllib.request.urlopen(req, timeout=30).read()
                sent = True
                break
            except Exception as exc:
                if attempt == 0:
                    print(f"mini_loop: telegram send retry for {chat_id}: {exc}", file=sys.stderr)
                    time.sleep(2)
                    continue
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
                if "signals" in s:
                    flags = ", ".join(k for k in _SIGNAL_KEYS if s.get(k))
                    fh.write(f"Signals: {s['signals']}/5 ({flags})\n\n")
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

    # Loop-aware gate: "active-project" (x/hn/dep) requires a project tie;
    # "anomaly" (finance) keys on a real, novel money anomaly instead.
    gate = spec.get("gate", "active-project")

    scored, surfaced = gate_items(items, context, spec.get("judge", ""), gate)
    if not scored:
        dur = time.monotonic() - t0
        _write_run_detail(
            name,
            {"run": _now_iso(), "grounding": grounding, "gate": gate,
             "context": context, "gathered": items, "scored": [], "surfaced": []},
        )
        _log_line(name, "FAIL", f"gathered={n_gathered} judge returned nothing dur={dur:.1f}s")
        return 1

    sent = False
    if surfaced:
        # KB keeps the full record; Telegram stays terse (and silent if nothing
        # survives the gate).
        if spec.get("kb"):
            write_kb_note(name, surfaced)
        if spec.get("telegram"):
            sent = send_telegram(name, surfaced, gate)

    stage_a = sum(1 for e in scored if _passes_stage_a(e, gate))
    _write_run_detail(
        name,
        {
            "run": _now_iso(),
            "grounding": grounding,
            "gate": gate,
            "min_signals": MIN_SIGNALS,
            "context": context,
            "gathered": items,
            "scored": scored,
            "stage_a_survivors": stage_a,
            "surfaced": surfaced,
        },
    )

    dur = time.monotonic() - t0
    tg = "tg=sent" if sent else "tg=silent"
    _log_line(
        name,
        "OK",
        f"gathered={n_gathered} stageA={stage_a} surfaced={len(surfaced)} {tg} "
        f"gate={gate} ground={grounding} dur={dur:.1f}s",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
