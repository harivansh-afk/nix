#!/usr/bin/env python3
"""hn_feed_scan.py - print the Hacker News front page as text, one story a line.

The gather step for the hn-life-scan mini-loop. Fetches the front page via the
Algolia HN API (no key, no browser) and emits each story as:

    <title> | <url or HN link> | <points>pts

Deliberately a separate deterministic entrypoint (like x-feed-scan) so the loop's
gather is a single command. On any failure it prints nothing and exits 0 - the
loop treats empty gather as SKIP.

Env:
  HN_HITS   how many front-page stories to fetch (default 40)
"""

import json
import os
import sys
import urllib.request

API = "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage={n}"


def main() -> int:
    try:
        n = int(os.environ.get("HN_HITS", "40") or "40")
    except ValueError:
        n = 40

    req = urllib.request.Request(
        API.format(n=n), headers={"User-Agent": "mini-loops"}
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.load(resp)
    except Exception as exc:
        print(f"hn-feed: HN Algolia unreachable: {exc}", file=sys.stderr)
        return 0

    hits = data.get("hits") if isinstance(data, dict) else None
    if not isinstance(hits, list):
        return 0

    for hit in hits:
        if not isinstance(hit, dict):
            continue
        title = (hit.get("title") or "").strip()
        if not title:
            continue
        object_id = str(hit.get("objectID", "")).strip()
        hn_link = f"https://news.ycombinator.com/item?id={object_id}"
        url = (hit.get("url") or "").strip() or hn_link
        points = hit.get("points") or 0
        print(f"{title} | {url} | {points}pts")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
