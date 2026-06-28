#!/usr/bin/env python3
"""Run a single browser-use task headless against the local brain and print the
final result text to stdout.

This is DOM-extraction only: the local brain (qwen3.6-35b-a3b at
127.0.0.1:18080) is text-only with no vision/mmproj, so use_vision is forced
False - browser-use feeds the model the serialized DOM instead of screenshots.

Chromium comes from the nix store (BROWSER_USE_CHROMIUM); browser-use launches
it directly over CDP (no Playwright, no browser download).

Env (all set by the `browse` wrapper / the nix module):
  BROWSER_USE_BRAIN_URL    OpenAI-compatible base url (default 127.0.0.1:18080/v1)
  BROWSER_USE_BRAIN_MODEL  model id (default qwen3.6-35b-a3b)
  BROWSER_USE_CHROMIUM     path to the chromium binary (required)
  BROWSER_USE_PROFILE_DIR  persistent user-data dir (optional, for logged-in sites)
  BROWSER_USE_STORAGE_STATE path to a cookies/storage_state json (optional)
  BROWSER_USE_MAX_STEPS    max agent steps (default 25)

Usage: run_task.py "<task string>"
Exit: 0 with result text on stdout; non-zero with a message on stderr on error.
"""

import asyncio
import os
import sys


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    return v if v not in (None, "") else default


async def _main() -> int:
    task = " ".join(sys.argv[1:]).strip()
    if not task:
        print("browse: no task given", file=sys.stderr)
        return 2

    chromium = _env("BROWSER_USE_CHROMIUM")
    if not chromium or not os.path.exists(chromium):
        print(f"browse: chromium not found at {chromium!r}", file=sys.stderr)
        return 2

    base_url = _env("BROWSER_USE_BRAIN_URL", "http://127.0.0.1:18080/v1")
    model = _env("BROWSER_USE_BRAIN_MODEL", "qwen3.6-35b-a3b")
    profile_dir = _env("BROWSER_USE_PROFILE_DIR")
    storage_state = _env("BROWSER_USE_STORAGE_STATE")
    try:
        max_steps = int(_env("BROWSER_USE_MAX_STEPS", "25") or "25")
    except ValueError:
        max_steps = 25

    # Imported here (not at module top) so a missing/half-installed venv fails
    # with a clear message rather than at parse time.
    from browser_use import Agent, BrowserProfile, BrowserSession, ChatOpenAI

    llm = ChatOpenAI(
        model=model,
        base_url=base_url,
        # Local llama.cpp needs no real key; browser-use still wants a value.
        api_key=_env("BROWSER_USE_BRAIN_KEY", "local"),
        temperature=0.3,
        # The local model is not guaranteed to honor OpenAI response_format /
        # structured-output, so put the action JSON schema in the system prompt
        # instead. This keeps the agent loop working on a plain chat model.
        add_schema_to_system_prompt=True,
    )

    profile = BrowserProfile(
        executable_path=chromium,
        headless=True,
        # Persist the profile when a dir is given so logged-in sessions (e.g. X)
        # survive across runs.
        user_data_dir=profile_dir,
        # storage_state and a real user_data_dir conflict; only pass cookies when
        # not using a persistent profile.
        storage_state=storage_state if not profile_dir else None,
    )
    session = BrowserSession(browser_profile=profile)

    agent = Agent(
        task=task,
        llm=llm,
        browser_session=session,
        # DOM mode: the brain is text-only, so never send screenshots.
        use_vision=False,
    )

    try:
        history = await agent.run(max_steps=max_steps)
    finally:
        try:
            await session.kill()
        except Exception:
            pass

    result = history.final_result()
    if result:
        print(result)
        return 0
    print("browse: agent finished without a final result", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
