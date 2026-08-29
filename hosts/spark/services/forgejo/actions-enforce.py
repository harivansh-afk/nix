"""Clamp Forgejo Actions to the mirror-manifest allowlist.

Reads FORGEJO_MIRROR_MANIFEST, finds every repo with the Actions unit on in
the forgejo SQLite db (repo_unit.type = 10) and PATCHes has_actions through
the API so the set matches actions_enabled_repos exactly.

Environment: FORGEJO_API, FORGEJO_MIRROR_MANIFEST, FORGEJO_DB, FORGEJO_TOKEN.
"""

import json
import os
import sqlite3
import subprocess
import sys

API = os.environ["FORGEJO_API"]
MANIFEST = os.environ["FORGEJO_MIRROR_MANIFEST"]
DB = os.environ["FORGEJO_DB"]
TOKEN = os.environ.get("FORGEJO_TOKEN")


def main() -> int:
    if not os.path.isfile(MANIFEST):
        print("manifest not readable")
        return 0
    if not os.path.isfile(DB):
        print("forgejo db not readable")
        return 0
    if not TOKEN:
        print("missing FORGEJO_TOKEN")
        return 1

    with open(MANIFEST) as f:
        allowlist = set(json.load(f).get("actions_enabled_repos", []))

    conn = sqlite3.connect(DB)
    try:
        rows = conn.execute(
            """
            SELECT u.lower_name || '/' || r.lower_name
            FROM repo_unit ru
            JOIN repository r ON r.id = ru.repo_id
            JOIN user u ON u.id = r.owner_id
            WHERE ru.type = 10
            """
        ).fetchall()
    finally:
        conn.close()
    actions_on = {str(row[0]) for row in rows if row[0]}

    for repo in sorted(actions_on - allowlist):
        print(f"  disabling actions: {repo}")
        patch(repo, False)
    for repo in sorted(allowlist - actions_on):
        print(f"  enabling actions: {repo}")
        patch(repo, True)
    return 0


def patch(repo: str, enable: bool) -> None:
    result = subprocess.run(
        [
            "curl",
            "-fsS",
            "-X",
            "PATCH",
            "-H",
            f"Authorization: token {TOKEN}",
            "-H",
            "Content-Type: application/json",
            "-d",
            json.dumps({"has_actions": enable}),
            f"{API}/repos/{repo}",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        print(f"    PATCH failed for {repo}: {result.stderr.decode().strip()}")


if __name__ == "__main__":
    sys.exit(main())
