#!/usr/bin/env python3
"""Scan the logged-in X (Twitter) home feed and print the latest posts as text.

Loads the captured storage_state (cookies) into a headless Chromium and uses a
browser-use agent (DOM mode, local brain) to read the home/following timeline
and return the latest ~N posts, one per line as "<author> | <text> | <url>".

This is the gather step for the x-life-scan mini-loop. It is deliberately a
separate entrypoint from `browse` so the loop's gather is a single deterministic
command. Mirrors dots/browser-use/run_task.py for the env + agent wiring.

If no logged-in session is available (no storage_state, or it lacks auth_token),
prints nothing and exits 0 - the loop treats empty gather as SKIP.

Env (set by the mini-loops module):
  BROWSER_USE_STORAGE_STATE  storage_state json with the X cookies (required)
  BROWSER_USE_CHROMIUM       path to the chromium binary (required)
  BROWSER_USE_BRAIN_URL      OpenAI-compatible base url (default 127.0.0.1:18080/v1)
  BROWSER_USE_BRAIN_MODEL    model id (default qwen3.6-35b-a3b)
  X_FEED_COUNT               how many posts to return (default 30)
  BROWSER_USE_MAX_STEPS      max agent steps (default 25)
"""

import asyncio
import json
import os
import sys


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    return v if v not in (None, "") else default


def _has_session(path: str | None) -> bool:
    if not path or not os.path.exists(path):
        return False
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return False
    names = {c.get("name") for c in data.get("cookies", [])}
    return "auth_token" in names


async def _main() -> int:
    storage_state = _env("BROWSER_USE_STORAGE_STATE")
    if not _has_session(storage_state):
        # No logged-in session: emit nothing, let the caller SKIP.
        print("x-feed: no logged-in X session; nothing to scan", file=sys.stderr)
        return 0

    chromium = _env("BROWSER_USE_CHROMIUM")
    if not chromium or not os.path.exists(chromium):
        print(f"x-feed: chromium not found at {chromium!r}", file=sys.stderr)
        return 0

    base_url = _env("BROWSER_USE_BRAIN_URL", "http://127.0.0.1:18080/v1")
    model = _env("BROWSER_USE_BRAIN_MODEL", "qwen3.6-35b-a3b")
    try:
        count = int(_env("X_FEED_COUNT", "30") or "30")
    except ValueError:
        count = 30
    try:
        max_steps = int(_env("BROWSER_USE_MAX_STEPS", "25") or "25")
    except ValueError:
        max_steps = 25

    from browser_use import Agent, BrowserProfile, BrowserSession, ChatOpenAI

    llm = ChatOpenAI(
        model=model,
        base_url=base_url,
        api_key=_env("BROWSER_USE_BRAIN_KEY", "local"),
        temperature=0.3,
        add_schema_to_system_prompt=True,
    )

    profile = BrowserProfile(
        executable_path=chromium,
        headless=True,
        storage_state=storage_state,
    )
    session = BrowserSession(browser_profile=profile)

    task = (
        "Go to https://x.com/home (you are already logged in). Scroll the home "
        f"timeline to load recent posts. Return ONLY the latest {count} posts as "
        'plain text, one post per line, each formatted exactly as '
        '"<author handle> | <full post text on one line> | <post url>". '
        "Skip ads and promoted posts. Do not add any commentary or numbering."
    )

    agent = Agent(
        task=task,
        llm=llm,
        browser_session=session,
        use_vision=False,
    )

    try:
        history = await agent.run(max_steps=max_steps)
    except Exception as exc:
        print(f"x-feed: agent error: {exc}", file=sys.stderr)
        return 0
    finally:
        try:
            await session.kill()
        except Exception:
            pass

    result = history.final_result()
    if result:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
