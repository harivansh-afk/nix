import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


DATABASE = os.environ.get(
    "WEBSITE_COUNTER_DATABASE", "/var/lib/website-counter/counter.sqlite3"
)
SEED = int(os.environ["WEBSITE_COUNTER_SEED"])
SEED_CUTOFF = os.environ["WEBSITE_COUNTER_SEED_CUTOFF"]
HOST = "127.0.0.1"
PORT = int(os.environ.get("WEBSITE_COUNTER_PORT", "8230"))


def connect():
    return sqlite3.connect(DATABASE, timeout=5)


def initialize():
    with connect() as database:
        database.execute("PRAGMA journal_mode=WAL")
        database.execute(
            """
            CREATE TABLE IF NOT EXISTS counters (
                name TEXT PRIMARY KEY,
                value INTEGER NOT NULL CHECK (value >= 0)
            )
            """
        )
        database.execute(
            """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
        database.execute(
            "INSERT OR IGNORE INTO counters (name, value) VALUES ('page_loads', ?)",
            (SEED,),
        )
        database.executemany(
            "INSERT OR IGNORE INTO metadata (key, value) VALUES (?, ?)",
            (
                ("seed_source", "Cloudflare RUM requestHost=harivan.sh"),
                ("seed_value", str(SEED)),
                ("seed_cutoff", SEED_CUTOFF),
            ),
        )


def current_value():
    with connect() as database:
        row = database.execute(
            "SELECT value FROM counters WHERE name = 'page_loads'"
        ).fetchone()
    if row is None:
        raise RuntimeError("page_loads counter is missing")
    return row[0]


def increment():
    with connect() as database:
        database.execute("BEGIN IMMEDIATE")
        database.execute(
            "UPDATE counters SET value = value + 1 WHERE name = 'page_loads'"
        )
        row = database.execute(
            "SELECT value FROM counters WHERE name = 'page_loads'"
        ).fetchone()
    if row is None:
        raise RuntimeError("page_loads counter is missing")
    return row[0]


class CounterHandler(BaseHTTPRequestHandler):
    server_version = "website-counter"
    sys_version = ""

    def do_GET(self):
        if urlsplit(self.path).path != "/counter":
            self.send_error(404)
            return
        body = f"{current_value()}\n".encode()
        self.send_response(200)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if urlsplit(self.path).path != "/counter/hit":
            self.send_error(404)
            return
        if self.headers.get("Origin") != "https://harivan.sh":
            self.send_error(403)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if length < 0 or length > 4096:
            self.send_error(413)
            return
        if length:
            self.rfile.read(length)
        increment()
        self.send_response(204)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format, *args):
        return


def main():
    initialize()
    server = ThreadingHTTPServer((HOST, PORT), CounterHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
