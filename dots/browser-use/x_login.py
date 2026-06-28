#!/usr/bin/env python3
"""Capture a logged-in X (Twitter) session as a Playwright storage_state JSON.

Two modes:

  Headed login (default): launches a VISIBLE Chromium at x.com, waits for the
  user to log in by hand, then writes the session (cookies via CDP) to the
  storage_state path. A display is required - run this once over `ssh -X spark`.

  Env import (no display): if X_AUTH_TOKEN and X_CT0 are set, skips the browser
  entirely and writes a minimal storage_state.json with those two cookies (the
  pair X needs for an authenticated read session). Useful headless.

Output: storage_state.json at $BROWSER_USE_STORAGE_STATE (mode 0600), which the
x-life-scan mini-loop loads so its feed gather is logged-in.

browser-use 0.13.x: BrowserSession.export_storage_state(path) extracts cookies
via CDP (verified against 0.13.1) and writes a Playwright-compatible JSON
({"cookies":[...],"origins":[...]}). localStorage origins are empty in this
version; the X auth cookies (auth_token + ct0) are what matter.

Env (set by the browse-x-login wrapper / the nix module):
  BROWSER_USE_STORAGE_STATE  output path for the storage_state json (required)
  BROWSER_USE_CHROMIUM       path to the chromium binary (required for headed)
  X_LOGIN_TIMEOUT            seconds to wait for a manual login (default 300)
  X_AUTH_TOKEN, X_CT0        optional cookie pair for headless import
"""

import asyncio
import json
import os
import stat
import sys
import time


def _env(name: str, default: str | None = None) -> str | None:
    v = os.environ.get(name)
    return v if v not in (None, "") else default


def _write_secure(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)  # 0600


def _import_from_env(path: str, token: str, ct0: str) -> int:
    """Write a storage_state with just the X auth cookie pair (headless path)."""
    # Far-future expiry; X rotates these server-side anyway.
    expires = int(time.time()) + 60 * 60 * 24 * 365
    cookies = [
        {
            "name": "auth_token",
            "value": token,
            "domain": ".x.com",
            "path": "/",
            "expires": expires,
            "httpOnly": True,
            "secure": True,
            "sameSite": "None",
        },
        {
            "name": "ct0",
            "value": ct0,
            "domain": ".x.com",
            "path": "/",
            "expires": expires,
            "httpOnly": False,
            "secure": True,
            "sameSite": "Lax",
        },
    ]
    _write_secure(path, {"cookies": cookies, "origins": []})
    print(f"x-login: imported auth_token+ct0 from env -> {path}")
    return 0


async def _headed_login(path: str, chromium: str, timeout: int) -> int:
    # Imported here so a missing/half-installed venv fails with a clear message
    # rather than at parse time (mirrors run_task.py).
    from browser_use import BrowserProfile, BrowserSession

    profile = BrowserProfile(
        executable_path=chromium,
        headless=False,
    )
    session = BrowserSession(browser_profile=profile)

    print("x-login: opening a visible Chromium. Log in to X in the window.")
    print(f"x-login: you have {timeout}s; the session is saved automatically after.")
    try:
        await session.start()
        # Drive the visible browser to x.com's login page.
        try:
            await session.navigate("https://x.com/login")
        except Exception:
            # API name drift across point releases: fall back to a CDP create.
            try:
                await session.create_new_tab("https://x.com/login")
            except Exception:
                print("x-login: could not auto-open x.com; browse there manually.")

        # Give the user time to complete an interactive login by hand. We cannot
        # reliably detect "logged in" headlessly, so we wait a fixed window and
        # then snapshot whatever cookies exist.
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            await asyncio.sleep(5)
            try:
                cookies = await session.cookies()
            except Exception:
                cookies = []
            names = {c.get("name") for c in cookies} if cookies else set()
            if "auth_token" in names and "ct0" in names:
                print("x-login: detected auth_token + ct0; saving session.")
                break

        await session.export_storage_state(path)
    finally:
        try:
            await session.kill()
        except Exception:
            pass

    # Verify the saved file actually contains the auth cookies.
    try:
        with open(path, encoding="utf-8") as fh:
            saved = json.load(fh)
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)  # 0600
        names = {c.get("name") for c in saved.get("cookies", [])}
    except Exception as exc:
        print(f"x-login: failed to read back {path}: {exc}", file=sys.stderr)
        return 1

    if "auth_token" in names:
        print(f"x-login: saved logged-in session -> {path}")
        return 0
    print(
        "x-login: saved a session but auth_token is missing - did the login "
        "complete? Re-run and finish logging in before the timeout.",
        file=sys.stderr,
    )
    return 1


async def _main() -> int:
    path = _env("BROWSER_USE_STORAGE_STATE")
    if not path:
        print("x-login: BROWSER_USE_STORAGE_STATE not set", file=sys.stderr)
        return 2

    token = _env("X_AUTH_TOKEN")
    ct0 = _env("X_CT0")
    if token and ct0:
        return _import_from_env(path, token, ct0)

    chromium = _env("BROWSER_USE_CHROMIUM")
    if not chromium or not os.path.exists(chromium):
        print(f"x-login: chromium not found at {chromium!r}", file=sys.stderr)
        return 2
    try:
        timeout = int(_env("X_LOGIN_TIMEOUT", "300") or "300")
    except ValueError:
        timeout = 300
    return await _headed_login(path, chromium, timeout)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
