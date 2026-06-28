#!/usr/bin/env python3
"""dep_release_scan.py - print NEW releases of watched dependency repos as text.

The gather step for the dep-release-watch mini-loop. For each repo in WATCHLIST it
queries the GitHub public API (`/repos/{owner}/{repo}/releases/latest`, no token)
and emits a line ONLY when the latest release is newer than the one last seen.

    <owner/repo> <tag> | <release name> | <first ~500 chars of body> | <url>

Last-seen state lives in $MINI_LOOPS_DIR/state/dep-release-watch.json so each
release is reported once. On the FIRST run (empty state) it records the current
latest tags WITHOUT emitting anything, to avoid a flood of "new" releases that are
just the existing latest of every repo; it prints a SKIP note to stderr.

On any per-repo error (rate limit, 404, network) the repo is skipped quietly so a
single bad repo does not break the scan. On a total failure it prints nothing and
exits 0 - the loop treats empty gather as SKIP.

Env:
  MINI_LOOPS_DIR   state root (default /var/lib/mini-loops)
"""

import json
import os
import sys
import urllib.error
import urllib.request

# ---------------------------------------------------------------------------
# WATCHLIST - the dependency repos to watch for major releases.
# EDIT THIS LIST: add "owner/repo" lines for dependencies of your active
# projects. Keep it small and curated; the gate only pings on MAJOR releases.
#
# NOTE: every repo here MUST publish GitHub *Releases* - this scan hits
# /repos/{owner}/{repo}/releases/latest. Repos that ship via git TAGS only
# (no Releases) always 404 and are useless here, so do not add them. Examples
# that were removed for exactly this reason: NixOS/nix and QwenLM/Qwen3 (both
# tag-only, zero GitHub releases). A bad repo is skipped silently (no crash),
# but it will never surface anything.
# ---------------------------------------------------------------------------
WATCHLIST = [
    "ggml-org/llama.cpp",
    "browser-use/browser-use",
    "topoteretes/cognee",
    "microsoft/playwright",
]

STATE_DIR = os.path.join(
    os.environ.get("MINI_LOOPS_DIR", "/var/lib/mini-loops"), "state"
)
STATE_FILE = os.path.join(STATE_DIR, "dep-release-watch.json")


def _load_state() -> dict:
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_state(state: dict) -> None:
    os.makedirs(STATE_DIR, exist_ok=True)
    try:
        with open(STATE_FILE, "w", encoding="utf-8") as fh:
            json.dump(state, fh, indent=2)
    except Exception as exc:
        print(f"dep-release: state write failed: {exc}", file=sys.stderr)


def _latest_release(repo: str) -> dict | None:
    """Return {tag, name, body, url} for the repo's latest release, or None."""
    url = f"https://api.github.com/repos/{repo}/releases/latest"
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
    except urllib.error.HTTPError as exc:
        # 404 = the repo publishes no GitHub Releases (tag-only). Expected for a
        # misconfigured watchlist entry; skip it silently instead of logging on
        # every run. Other HTTP errors (rate limit etc.) are worth a note.
        if exc.code != 404:
            print(f"dep-release: {repo} fetch failed: {exc}", file=sys.stderr)
        return None
    except Exception as exc:
        print(f"dep-release: {repo} fetch failed: {exc}", file=sys.stderr)
        return None
    if not isinstance(data, dict):
        return None
    tag = str(data.get("tag_name", "")).strip()
    if not tag:
        return None
    return {
        "tag": tag,
        "name": (data.get("name") or "").strip(),
        "body": (data.get("body") or "").strip(),
        "url": (data.get("html_url") or "").strip(),
    }


def main() -> int:
    state = _load_state()
    first_run = not state

    new_lines: list[str] = []
    for repo in WATCHLIST:
        rel = _latest_release(repo)
        if rel is None:
            continue
        last_seen = state.get(repo)
        # Always record the current latest tag.
        state[repo] = rel["tag"]
        if first_run:
            continue  # baseline only; do not surface on first run
        if rel["tag"] == last_seen:
            continue  # already seen this release
        body = rel["body"].replace("\r\n", "\n").replace("\n", " ").strip()
        body = body[:500]
        name = rel["name"] or rel["tag"]
        new_lines.append(f"{repo} {rel['tag']} | {name} | {body} | {rel['url']}")

    _save_state(state)

    if first_run:
        print(
            "dep-release: baseline recorded for "
            f"{len(state)} repos (no releases surfaced on first run)",
            file=sys.stderr,
        )
        return 0

    for line in new_lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
