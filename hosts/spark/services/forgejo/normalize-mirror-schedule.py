"""Pin every pull mirror to one interval, staggered by repo id, and drop
day-old cancelled action tasks. Runs before each forgejo start.

Environment: FORGEJO_DB, MIRROR_INTERVAL_SECONDS.
"""

import os
import sqlite3
import sys

DB = os.environ["FORGEJO_DB"]
INTERVAL = int(os.environ["MIRROR_INTERVAL_SECONDS"])

if not os.path.isfile(DB):
    sys.exit(0)

conn = sqlite3.connect(DB)
try:
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute(
        """
        UPDATE mirror
        SET interval = ?,
            next_update_unix = CAST(strftime('%s', 'now') AS INTEGER) + (repo_id % ?)
        """,
        (INTERVAL * 1_000_000_000, INTERVAL),
    )
    conn.execute(
        """
        DELETE FROM action_task
        WHERE status IN (6)
          AND updated < CAST(strftime('%s', 'now', '-1 day') AS INTEGER)
        """
    )
    conn.execute("PRAGMA optimize")
    conn.commit()
finally:
    conn.close()
