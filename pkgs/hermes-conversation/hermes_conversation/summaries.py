"""Derived, profile-local summaries. No conversation transcript or task state is rewritten."""

import asyncio
import contextvars
import hashlib
import json
import logging
import sqlite3
import threading
import time
import uuid
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)


def digest(messages):
    return hashlib.sha256(
        json.dumps(messages, ensure_ascii=False, sort_keys=True).encode()
    ).hexdigest()


@dataclass(frozen=True)
class Summary:
    covered: int = 0
    digest: str = ""
    text: str = ""


class Summaries:
    def __init__(self, path, llm):
        self.path = Path(path)
        self.llm = llm
        self.busy = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with closing(self.connect()) as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS summaries (
                session TEXT PRIMARY KEY, covered INTEGER NOT NULL DEFAULT 0,
                digest TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '',
                claim TEXT, lease REAL NOT NULL DEFAULT 0, updated REAL NOT NULL DEFAULT 0,
                pending_covered INTEGER NOT NULL DEFAULT 0, pending_digest TEXT NOT NULL DEFAULT ''
            )""")

    def connect(self):
        return sqlite3.connect(self.path, timeout=0.05)

    def read(self, session, messages):
        with closing(self.connect()) as db, db:
            row = db.execute(
                "SELECT covered, digest, text, claim, pending_covered, pending_digest FROM summaries WHERE session=?",
                (session,),
            ).fetchone()
            if (
                row
                and row[3]
                and (row[4] > len(messages) or row[5] != digest(messages[: row[4]]))
            ):
                db.execute(
                    "UPDATE summaries SET claim=NULL, lease=0 WHERE session=?",
                    (session,),
                )
            if (
                row
                and 0 < row[0] <= len(messages)
                and row[1] == digest(messages[: row[0]])
            ):
                return Summary(*row[:3])
            if row and row[0]:
                db.execute("DELETE FROM summaries WHERE session=?", (session,))
        return Summary()

    def invalidate(self, session):
        with closing(self.connect()) as db, db:
            db.execute("DELETE FROM summaries WHERE session=?", (session,))

    def schedule(self, session, messages, previous):
        if (
            not session
            or len(messages) <= previous.covered
            or not self.busy.acquire(blocking=False)
        ):
            return
        claim = uuid.uuid4().hex
        try:
            with closing(self.connect()) as db, db:
                db.execute(
                    "INSERT OR IGNORE INTO summaries(session) VALUES (?)", (session,)
                )
                acquired = db.execute(
                    "UPDATE summaries SET claim=?, lease=?, pending_covered=?, pending_digest=? "
                    "WHERE session=? AND lease < ? AND covered=? AND digest=?",
                    (
                        claim,
                        time.time() + 45,
                        len(messages),
                        digest(messages),
                        session,
                        time.time(),
                        previous.covered,
                        previous.digest,
                    ),
                ).rowcount
            if not acquired:
                self.busy.release()
                return
            context = contextvars.copy_context()
            threading.Thread(
                target=context.run,
                args=(self.generate, session, messages, previous, claim),
                name="hermes-conversation-summary",
                daemon=True,
            ).start()
        except Exception:
            self.busy.release()
            raise

    def generate(self, session, messages, previous, claim):
        succeeded = False
        try:
            prompt = (Path(__file__).parent / "summary.md").read_text()

            async def summarize():
                return await asyncio.wait_for(
                    self.llm.acomplete_structured(
                        instructions=prompt,
                        input=[
                            {
                                "type": "text",
                                "text": json.dumps(
                                    {
                                        "previous_summary": previous.text,
                                        "dialogue": messages[previous.covered :],
                                    },
                                    ensure_ascii=False,
                                ),
                            }
                        ],
                        json_schema={
                            "type": "object",
                            "properties": {
                                "summary": {
                                    "type": "string",
                                    "minLength": 1,
                                    "maxLength": 12000,
                                }
                            },
                            "required": ["summary"],
                            "additionalProperties": False,
                        },
                        max_tokens=3000,
                        timeout=30,
                        task="conversation_summary",
                        purpose="conversation.summary",
                    ),
                    timeout=35,
                )

            result = asyncio.run(summarize())
            text = (result.parsed or {}).get("summary", "")
            if not isinstance(text, str) or not text.strip() or len(text) > 12000:
                raise ValueError("Summary was incomplete or invalid")
            with closing(self.connect()) as db, db:
                db.execute(
                    "UPDATE summaries SET covered=?, digest=?, text=?, claim=NULL, lease=0, updated=? "
                    "WHERE session=? AND claim=?",
                    (
                        len(messages),
                        digest(messages),
                        text,
                        time.time(),
                        session,
                        claim,
                    ),
                )
            succeeded = True
        except Exception:
            log.warning(
                "Background conversation summary failed; retaining previous context",
                exc_info=True,
            )
        finally:
            try:
                with closing(self.connect()) as db, db:
                    db.execute(
                        "UPDATE summaries SET claim=NULL, lease=? WHERE session=? AND claim=?",
                        (0 if succeeded else time.time() + 60, session, claim),
                    )
            except sqlite3.Error:
                log.warning(
                    "Could not release summary lease; it will expire", exc_info=True
                )
            self.busy.release()
