import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import downloads_connector as connector


class DownloadsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        self.root = base / "Downloads"
        self.root.mkdir()
        self.staging = base / "staging"
        self.denied = self.root / "security"
        self.denied.mkdir()
        config = patch.multiple(connector, ROOT=self.root, STAGING=self.staging, DENYLIST=[self.denied])
        config.start()
        self.addCleanup(config.stop)

    def run_connector(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(connector.main(), 0)

    def test_unchanged_file_is_not_extracted_or_rewritten(self):
        source = self.root / "note.txt"
        source.write_text("First version")
        self.run_connector()
        note = connector.note_path(source)
        before = note.read_bytes(), note.stat().st_mtime_ns
        self.assertEqual(connector.existing_hash(note), connector.sha256_file(source))
        with patch.object(connector, "extract_text", side_effect=AssertionError("dedupe missed")):
            self.run_connector()
        self.assertEqual((note.read_bytes(), note.stat().st_mtime_ns), before)
        source.write_text("Second version")
        self.run_connector()
        self.assertIn("Second version", note.read_text())

    def test_hash_in_body_is_not_frontmatter(self):
        note = self.root / "metadata.md"
        note.write_text("---\nsource_kind: downloads\n---\ncontent_hash: not metadata\n")
        self.assertIsNone(connector.existing_hash(note))

    def test_move_into_denylist_removes_old_note_without_reading_source(self):
        source = self.root / "note.txt"
        source.write_text("Synthetic private document")
        self.run_connector()
        note = connector.note_path(source)
        source.rename(self.denied / source.name)
        with patch.object(connector, "sha256_file", side_effect=AssertionError("read denied file")):
            self.run_connector()
        self.assertFalse(note.exists())
        self.assertTrue((self.denied / source.name).exists())

    def test_hidden_symlink_and_deleted_sources_are_removed(self):
        for name in ("hidden.txt", "link.txt", "gone.txt"):
            (self.root / name).write_text("Example")
        self.run_connector()
        notes = list(self.staging.glob("*.md"))
        (self.root / "hidden.txt").rename(self.root / ".hidden.txt")
        (self.root / "gone.txt").unlink()
        (self.root / "link.txt").unlink()
        (self.denied / "private.txt").write_text("Do not read")
        (self.root / "link.txt").symlink_to(self.denied / "private.txt")
        with patch.object(connector, "sha256_file", side_effect=AssertionError("read ineligible file")):
            self.run_connector()
        self.assertTrue(all(not note.exists() for note in notes))

    def test_incomplete_walk_keeps_previous_notes(self):
        source = self.root / "note.txt"
        source.write_text("Example")
        self.run_connector()
        note = connector.note_path(source)
        def incomplete_walk(root, onerror):
            onerror(PermissionError("unreadable directory"))
            return iter(())
        with patch.object(connector.os, "walk", side_effect=incomplete_walk):
            self.run_connector()
        self.assertTrue(note.exists())
        with patch.object(connector, "ROOT", self.root / "missing"):
            self.run_connector()
        self.assertTrue(note.exists())

    def test_extraction_failure_preserves_note_and_unowned_files(self):
        source = self.root / "note.txt"
        source.write_text("Example")
        self.run_connector()
        note = connector.note_path(source)
        before = note.read_bytes()
        manual = self.staging / "manual.md"
        manual.write_text("User-authored note")
        linked = self.staging / "linked.md"
        linked.symlink_to(source)
        source.write_text("Changed")
        with patch.object(connector, "extract_text", side_effect=ValueError("bad document")):
            self.run_connector()
        self.assertEqual(note.read_bytes(), before)
        self.assertTrue(manual.exists())
        self.assertTrue(linked.is_symlink())


if __name__ == "__main__":
    unittest.main()
