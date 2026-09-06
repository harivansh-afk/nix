"""Seed recovered Options+ mappings before the vendor installer starts its agent."""

import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile


def seed(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name in ("settings", "macros"):
        target = destination / f"{name}.db"
        if target.exists():
            continue
        payload = (source / f"{name}.json").read_bytes()
        json.loads(payload)
        fd, temporary = tempfile.mkstemp(prefix=f".{name}-", dir=destination)
        os.close(fd)
        try:
            with sqlite3.connect(temporary) as db:
                db.executescript("""
                    CREATE TABLE data (
                        _id INTEGER PRIMARY KEY,
                        _date_created datetime default current_timestamp,
                        file BLOB NOT NULL
                    );
                    CREATE TABLE snapshots (
                        _id INTEGER PRIMARY KEY,
                        _date_created datetime default current_timestamp,
                        uuid TEXT NOT NULL,
                        label TEXT NOT NULL,
                        file BLOB NOT NULL
                    );
                """)
                db.execute("INSERT INTO data (_id, file) VALUES (1, ?)", (payload,))
            db.close()
            try:
                os.link(temporary, target)
                print(f"Seeded recovered Logitech mappings: {target}")
            except FileExistsError:
                pass
        finally:
            os.unlink(temporary)


if __name__ == "__main__":
    seed(Path(sys.argv[1]), Path(sys.argv[2]))
