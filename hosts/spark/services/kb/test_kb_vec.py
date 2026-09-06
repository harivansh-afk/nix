"""Exercise ingestion against a disposable Postgres cluster, never the live KB."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import psycopg2

import kb_vec


class AtomicIngestTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="kb-ingest-test-")
        cls.root = Path(cls.directory.name)
        cls.data = cls.root / "pg"
        cls.socket = cls.root / "socket"
        cls.socket.mkdir()
        subprocess.run(
            ["initdb", "-D", str(cls.data), "-A", "trust", "--no-locale", "-E", "UTF8"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                "pg_ctl",
                "-D",
                str(cls.data),
                "-l",
                str(cls.root / "postgres.log"),
                "-o",
                f"-k {cls.socket} -c listen_addresses='' -p 19473",
                "-w",
                "start",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        cls.addClassCleanup(cls.stop_cluster)
        cls.pg = dict(host=str(cls.socket), port=19473, dbname="postgres")
        cls.document = cls.root / "document.md"
        cls.document.write_text("new document")
        cls.vector = [0.01] * 1024

    @classmethod
    def stop_cluster(cls):
        subprocess.run(
            ["pg_ctl", "-D", str(cls.data), "-m", "immediate", "-w", "stop"],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        cls.directory.cleanup()

    def setUp(self):
        self.con = psycopg2.connect(**self.pg)
        self.addCleanup(self.con.close)
        with self.con, self.con.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
            cur.execute("DROP TABLE IF EXISTS kb_vec CASCADE")
            cur.execute(
                "CREATE TABLE kb_vec(id bigserial primary key, source text, path text,"
                " chunk int, txt text CHECK (txt <> 'reject replacement'), emb vector(1024))"
            )
            cur.execute(
                "INSERT INTO kb_vec(source,path,chunk,txt,emb) VALUES ('old','old.md',0,'old document',%s)",
                (str(self.vector),),
            )
        self.addCleanup(patch.stopall)
        patch.object(kb_vec, "PG", self.pg).start()
        patch.object(kb_vec.glob, "glob", return_value=[str(self.document)]).start()

    def rows(self):
        with self.con, self.con.cursor() as cur:
            cur.execute("SET LOCAL lock_timeout = '1s'")
            cur.execute("SELECT txt FROM kb_vec ORDER BY id")
            return [r[0] for r in cur.fetchall()]

    def embed(self, texts):
        self.assertEqual(self.rows(), ["old document"])
        return [self.vector for _ in texts]

    def test_replaces_all_batches_only_after_embeddings(self):
        patch.object(
            kb_vec, "chunks", return_value=[f"new {i}" for i in range(33)]
        ).start()
        with patch.object(kb_vec, "embed", side_effect=self.embed):
            kb_vec.ingest()
        self.assertEqual(self.rows(), [f"new {i}" for i in range(33)])
        with self.con, self.con.cursor() as cur:
            cur.execute("SELECT indexname FROM pg_indexes WHERE tablename = 'kb_vec'")
            self.assertTrue(
                {"kb_vec_hnsw", "kb_vec_fts"} <= {r[0] for r in cur.fetchall()}
            )

    def test_embedding_failure_after_committed_staging_batch_preserves_old_rows(self):
        patch.object(kb_vec, "chunks", return_value=["new"] * 33).start()
        with patch.object(
            kb_vec, "embed", side_effect=[[self.vector] * 32, RuntimeError("offline")]
        ):
            with self.assertRaisesRegex(RuntimeError, "offline"):
                kb_vec.ingest()
        self.assertEqual(self.rows(), ["old document"])

    def test_incomplete_embedding_response_preserves_old_rows(self):
        with patch.object(kb_vec, "embed", return_value=[]):
            with self.assertRaisesRegex(ValueError, "count"):
                kb_vec.ingest()
        self.assertEqual(self.rows(), ["old document"])

    def test_invalid_vector_insert_preserves_old_rows(self):
        with patch.object(kb_vec, "embed", return_value=[[0.01]]):
            with self.assertRaises(psycopg2.Error):
                kb_vec.ingest()
        self.assertEqual(self.rows(), ["old document"])

    def test_final_insert_failure_rolls_back_truncate(self):
        patch.object(kb_vec, "chunks", return_value=["reject replacement"]).start()
        with patch.object(kb_vec, "embed", side_effect=self.embed):
            with self.assertRaises(psycopg2.IntegrityError):
                kb_vec.ingest()
        self.assertEqual(self.rows(), ["old document"])

    def test_empty_staging_replaces_previous_rows(self):
        patch.object(kb_vec.glob, "glob", return_value=[]).start()
        with patch.object(
            kb_vec, "embed", side_effect=AssertionError("unexpected embedding")
        ):
            kb_vec.ingest()
        self.assertEqual(self.rows(), [])


if __name__ == "__main__":
    unittest.main()
