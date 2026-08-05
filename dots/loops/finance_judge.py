#!/usr/bin/env python3
"""finance_judge.py - judge finance anomaly candidates with the LOCAL brain.

Stage one of the finance loop, and the only process that ever combines raw
finance data with a language model. It runs OUTSIDE the hermes gateway sandbox
(the gateway masks /var/lib/kb/staging/finance via InaccessiblePaths) in a
systemd unit that is allowed to reach loopback only, so the raw data provably
cannot leave the machine. The flow:

  1. Run the deterministic scanner (finance-anomaly-scan) for candidate lines:
     new subscriptions, price hikes, large charges, duplicate charges. The
     scanner dedupes via its own state, so every candidate here is NEW.
  2. Ask the local qwen brain (127.0.0.1) to write a short judged briefing.
     The brain ANNOTATES AND RANKS - it never drops a candidate. History: an
     earlier LLM skeptic dropped legitimate subscriptions (OpenAI, Claude) as
     "normal spending", which is exactly what Hari wants to see. Annotation is
     useful; vetoing is not allowed.
  3. Write the verdict note into $VERDICT_DIR (staging/loops/, which the
     gateway CAN read). A hermes cron job relays it to Hari over photon: hermes
     sees only this judged result, never the raw transactions or notes.

If the brain is unreachable the briefing degrades to the raw candidate lines,
marked unjudged - the loop never goes quiet because the model was down.

Env:
  FINANCE_SCAN_CMD  scanner executable (default finance-anomaly-scan on PATH)
  BRAIN_URL         chat completions endpoint (default http://127.0.0.1:18080/v1/chat/completions)
  BRAIN_MODEL       served model alias (default qwen3.6-35b-a3b)
  VERDICT_DIR       where verdict notes land (default /var/lib/kb/staging/loops/finance-anomaly-watch)
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCAN_CMD = os.environ.get("FINANCE_SCAN_CMD", "finance-anomaly-scan")
BRAIN_URL = os.environ.get(
    "BRAIN_URL", "http://127.0.0.1:18080/v1/chat/completions"
)
BRAIN_MODEL = os.environ.get("BRAIN_MODEL", "qwen3.6-35b-a3b")
VERDICT_DIR = Path(
    os.environ.get("VERDICT_DIR", "/var/lib/kb/staging/loops/finance-anomaly-watch")
)

SCAN_TIMEOUT = 120
BRAIN_TIMEOUT = 240

JUDGE_PROMPT = """\
You are the local finance judge for Hari's own accounts. Below are NEW spending
anomaly candidates, already computed deterministically and deduplicated: each
appears here exactly once, ever. Write a short briefing that will be relayed to
Hari on his phone.

Rules:
- EVERY candidate must appear in your briefing. You annotate and rank; you
  never drop. New subscriptions are the core value - even boring-looking ones.
- One line per candidate: what it is and why it matters (or "routine, just so
  you know" if it looks benign). Lead with the ones worth attention.
- Group under the headings: Subscriptions, Price hikes, Large charges,
  Duplicates - only the headings that apply.
- Plain text. No markdown tables, no emoji, no preamble, no sign-off.

Candidates:
"""


def log(message: str) -> None:
    print(f"finance-judge: {message}", file=sys.stderr)


def gather() -> list[str]:
    proc = subprocess.run(
        [SCAN_CMD], capture_output=True, text=True, timeout=SCAN_TIMEOUT
    )
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        log(f"scanner exited {proc.returncode}")
        return []
    return [line for line in (proc.stdout or "").splitlines() if line.strip()]


def judge(candidates: list[str]) -> tuple[str, bool]:
    """Return (briefing, judged). Falls back to raw lines when the brain fails."""
    body = json.dumps(
        {
            "model": BRAIN_MODEL,
            "messages": [
                {"role": "user", "content": JUDGE_PROMPT + "\n".join(candidates)}
            ],
            "temperature": 0.3,
            "max_tokens": 1200,
        }
    ).encode()
    request = urllib.request.Request(
        BRAIN_URL, data=body, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=BRAIN_TIMEOUT) as response:
            payload = json.load(response)
        briefing = payload["choices"][0]["message"]["content"].strip()
        if briefing:
            return briefing, True
        log("brain returned an empty completion")
    except (urllib.error.URLError, TimeoutError, KeyError, ValueError) as exc:
        log(f"brain unavailable ({exc}); relaying candidates unjudged")
    return "\n".join(candidates), False


def write_verdict(candidates: list[str], briefing: str, judged: bool) -> Path:
    run_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    note = "\n".join(
        [
            f"# finance-anomaly-watch {run_at[:10]}",
            "",
            "- Loop: finance-anomaly-watch",
            f"- Run: {run_at}",
            f"- Candidates: {len(candidates)}",
            f"- Judged: {'local brain (' + BRAIN_MODEL + ')' if judged else 'NO - brain unavailable, raw candidates'}",
            "",
            "## Briefing",
            "",
            briefing,
            "",
            "## Candidates",
            "",
            *[f"- {line}" for line in candidates],
            "",
        ]
    )
    VERDICT_DIR.mkdir(parents=True, exist_ok=True)
    target = VERDICT_DIR / f"{run_at}.md"
    tmp = target.with_suffix(".tmp")
    tmp.write_text(note, encoding="utf-8")
    tmp.replace(target)
    return target


def main() -> int:
    try:
        candidates = gather()
    except (OSError, subprocess.TimeoutExpired) as exc:
        log(f"scanner failed: {exc}")
        return 1
    if not candidates:
        log("no new candidates; quiet run")
        return 0
    briefing, judged = judge(candidates)
    target = write_verdict(candidates, briefing, judged)
    log(f"{len(candidates)} candidate(s) -> {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
