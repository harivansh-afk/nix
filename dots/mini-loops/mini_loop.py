#!/usr/bin/env python3
"""mini_loop.py - shared runner for the mini-loops framework.

A "mini-loop" is an autonomous life routine: gather items from a source, ground
them against the user's own life (kb-search), judge which have interesting
consequences, and act (Telegram ping + KB note). Each loop is a small spec; this
one runner executes any of them.

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
  b. ground  - kb-search each seed; assemble a compact "about Hari" block.
  c. judge   - POST items + context + judge prompt to the local brain; parse a
               JSON list of {item, relevant, why}. Robust to chatter/fences.
  d. act     - for each relevant item: Telegram (with the why) and/or KB note.
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
def ground(seeds: list[str]) -> str:
    """kb-search each seed; build a compact 'about Hari' context block."""
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
    """Ask the local brain which items have interesting consequences for Hari."""
    system = (
        judge_prompt
        + "\n\nYou are given (1) a CONTEXT block about Hari (from his personal "
        "knowledge base) and (2) a list of ITEMS. Decide which items have an "
        "interesting consequence for Hari given the context. Respond with ONLY a "
        "JSON array, one object per item you considered, each: "
        '{"item": "<short identifier or the item text/url>", "relevant": '
        'true|false, "why": "<one sentence: the concrete connection to Hari, or '
        'why it is noise>"}. Surface only genuinely relevant items as '
        "relevant=true; skip generic noise."
    )
    user = f"CONTEXT (about Hari):\n{context}\n\nITEMS:\n{items}"
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


def send_telegram(name: str, surfaced: list[dict]) -> None:
    token, users = _telegram_config()
    if not token or not users:
        print("mini_loop: no telegram token/allowlist; skipping telegram", file=sys.stderr)
        return
    lines = [f"[{name}] {len(surfaced)} surfaced:"]
    for s in surfaced:
        item = s["item"]
        why = s["why"]
        lines.append(f"• {item}\n  why: {why}")
    text = "\n".join(lines)
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    for chat_id in users:
        payload = json.dumps({"chat_id": chat_id, "text": text, "disable_web_page_preview": False}).encode()
        req = urllib.request.Request(url, payload, {"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=30).read()
        except Exception as exc:
            print(f"mini_loop: telegram send failed for {chat_id}: {exc}", file=sys.stderr)


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

    context = ground(spec.get("seeds", []))
    judged = judge(items, context, spec.get("judge", ""))
    if not judged:
        dur = time.monotonic() - t0
        _write_run_detail(name, {"run": _now_iso(), "gathered": items, "judged": [], "surfaced": []})
        _log_line(name, "FAIL", f"gathered={n_gathered} judge returned nothing dur={dur:.1f}s")
        return 1

    surfaced = [j for j in judged if j.get("relevant")]

    if surfaced:
        if spec.get("telegram"):
            send_telegram(name, surfaced)
        if spec.get("kb"):
            write_kb_note(name, surfaced)

    _write_run_detail(
        name,
        {
            "run": _now_iso(),
            "gathered": items,
            "judged": judged,
            "surfaced": surfaced,
        },
    )

    dur = time.monotonic() - t0
    _log_line(name, "OK", f"gathered={n_gathered} surfaced={len(surfaced)} dur={dur:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
