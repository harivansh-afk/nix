#!/usr/bin/env python3
"""Scan the logged-in X (Twitter) home feed and print the latest posts as text.

DETERMINISTIC scrape: loads the captured storage_state (cookies) into a headless
Chromium via Playwright and reads the home timeline DOM directly. NO LLM is used
here - the browser-use agentic loop was too slow on the local brain (every
navigation step timed out at 75s). The LLM only judges relevance later, in the
mini-loop runner. This is the gather step for the x-life-scan mini-loop.

Output: one post per line, formatted "<author> | <text on one line> | <url>".
If no logged-in session is available (no storage_state, or it lacks auth_token),
prints nothing and exits 0 - the loop treats empty gather as SKIP.

Env (set by the mini-loops module):
  BROWSER_USE_STORAGE_STATE  storage_state json with the X cookies (required)
  BROWSER_USE_CHROMIUM       path to the chromium binary (required; executable_path)
  X_FEED_COUNT               max posts to return (default 30)
  X_FEED_SCROLLS             scroll passes to load posts (default 6)
"""

import asyncio
import json
import os
import sys

# Playwright cookie fields; the captured storage_state carries extra CDP fields
# (size, priority, sourceScheme, ...) that Playwright rejects, so we whitelist.
_COOKIE_FIELDS = {"name", "value", "domain", "path", "expires", "httpOnly", "secure", "sameSite"}


def _env(name, default=None):
    v = os.environ.get(name)
    return v if v not in (None, "") else default


def _load_state(path):
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return None
    names = {c.get("name") for c in data.get("cookies", [])}
    if "auth_token" not in names:
        return None
    cookies = []
    for c in data.get("cookies", []):
        c2 = {k: v for k, v in c.items() if k in _COOKIE_FIELDS}
        if c2.get("sameSite") not in ("Strict", "Lax", "None"):
            c2["sameSite"] = "Lax"
        if c2.get("expires") in (None,):
            c2["expires"] = -1
        cookies.append(c2)
    return {"cookies": cookies, "origins": data.get("origins", [])}


_EXTRACT_JS = r"""() => {
  const out = [];
  for (const a of document.querySelectorAll('article')) {
    const t = a.querySelector('[data-testid=tweetText]');
    const u = a.querySelector('a[href*="/status/"]');
    const who = a.querySelector('[data-testid="User-Name"]');
    out.push({
      text: t ? t.innerText.replace(/\s+/g, ' ').trim() : '',
      url: u ? u.href : '',
      who: who ? who.innerText.replace(/\s+/g, ' ').trim() : ''
    });
  }
  return out;
}"""


async def _main():
    state = _load_state(_env("BROWSER_USE_STORAGE_STATE"))
    if state is None:
        print("x-feed: no logged-in X session; nothing to scan", file=sys.stderr)
        return 0

    chromium = _env("BROWSER_USE_CHROMIUM")
    if not chromium or not os.path.exists(chromium):
        print(f"x-feed: chromium not found at {chromium!r}", file=sys.stderr)
        return 0

    try:
        count = int(_env("X_FEED_COUNT", "30") or "30")
    except ValueError:
        count = 30
    try:
        scrolls = int(_env("X_FEED_SCROLLS", "6") or "6")
    except ValueError:
        scrolls = 6

    from playwright.async_api import async_playwright

    posts = []
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, executable_path=chromium)
        try:
            ctx = await browser.new_context(
                storage_state=state, viewport={"width": 1280, "height": 2000}
            )
            page = await ctx.new_page()
            await page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=45000)
            try:
                await page.wait_for_selector("article", timeout=20000)
            except Exception:
                print("x-feed: no posts loaded (session expired?)", file=sys.stderr)
                return 0
            for _ in range(scrolls):
                await page.mouse.wheel(0, 3000)
                await asyncio.sleep(1.5)
            posts = await page.evaluate(_EXTRACT_JS)
        finally:
            await browser.close()

    seen = set()
    n = 0
    for x in posts:
        url, text, who = x.get("url", ""), x.get("text", ""), x.get("who", "")
        if not url or not text or url in seen:
            continue
        seen.add(url)
        print(f"{who} | {text} | {url}")
        n += 1
        if n >= count:
            break
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
