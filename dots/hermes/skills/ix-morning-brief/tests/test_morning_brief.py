"""Tests for the ix morning brief gather and HTML renderer."""

from __future__ import annotations

import copy
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

SKILL_DIR = Path(__file__).resolve().parent.parent
GATHER_PATH = SKILL_DIR / "scripts" / "gather.py"
RENDER_PATH = SKILL_DIR / "scripts" / "render.py"
FIXTURE_PATH = SKILL_DIR / "fixtures" / "2026-08-05.json"
TEMPLATE_PATH = SKILL_DIR / "templates" / "brief.html"
PACIFIC = ZoneInfo("America/Los_Angeles")


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gather = load_module("ix_brief_gather", GATHER_PATH)
render = load_module("ix_brief_render", RENDER_PATH)


class GateTests(unittest.TestCase):
    def test_wakes_only_during_nine_pacific(self):
        self.assertFalse(
            gather.should_wake({}, datetime(2026, 8, 5, 8, 59, tzinfo=PACIFIC))
        )
        self.assertTrue(
            gather.should_wake({}, datetime(2026, 8, 5, 9, 0, tzinfo=PACIFIC))
        )
        self.assertTrue(
            gather.should_wake({}, datetime(2026, 8, 5, 9, 59, tzinfo=PACIFIC))
        )
        self.assertFalse(
            gather.should_wake({}, datetime(2026, 8, 5, 10, 0, tzinfo=PACIFIC))
        )

    def test_delivery_marker_suppresses_retries(self):
        now = datetime(2026, 8, 5, 9, 10, tzinfo=PACIFIC)
        self.assertFalse(gather.should_wake({"last_date": "2026-08-05"}, now))
        self.assertTrue(gather.should_wake({"last_date": "2026-08-04"}, now))

    def test_dst_days_are_keyed_to_local_clock(self):
        spring_utc = datetime(2026, 3, 8, 16, 5, tzinfo=timezone.utc)
        fall_utc = datetime(2026, 11, 1, 17, 5, tzinfo=timezone.utc)
        self.assertEqual(spring_utc.astimezone(PACIFIC).hour, 9)
        self.assertEqual(fall_utc.astimezone(PACIFIC).hour, 9)
        self.assertTrue(gather.should_wake({}, spring_utc.astimezone(PACIFIC)))
        self.assertTrue(gather.should_wake({}, fall_utc.astimezone(PACIFIC)))

    def test_force_bypasses_clock(self):
        now = datetime(2026, 8, 5, 2, 0, tzinfo=PACIFIC)
        self.assertTrue(
            gather.should_wake({"last_date": "2026-08-05"}, now, force=True)
        )


class RenderTests(unittest.TestCase):
    def fixture(self):
        return json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    def test_fixture_validates(self):
        data = self.fixture()
        self.assertEqual(render.validate(data), data)

    def test_workstream_cap_is_enforced(self):
        data = self.fixture()
        data["workstreams"].append(copy.deepcopy(data["workstreams"][0]))
        with self.assertRaisesRegex(ValueError, "1-3"):
            render.validate(data)

    def test_overlong_copy_is_rejected(self):
        data = self.fixture()
        data["summary"] = "x" * 261
        with self.assertRaisesRegex(ValueError, "260"):
            render.validate(data)

    def test_schema_version_is_enforced(self):
        data = self.fixture()
        data["schema"] = 2
        with self.assertRaisesRegex(ValueError, "schema must be 1"):
            render.validate(data)

    def test_render_is_self_contained_and_escapes_html(self):
        data = self.fixture()
        data["workstreams"][0]["title"] = "Cache <script>alert(1)</script> {{literal}}"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            content = root / "content.json"
            output = root / "brief.html"
            content.write_text(json.dumps(data), encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(RENDER_PATH),
                    "--input",
                    str(content),
                    "--output",
                    str(output),
                    "--template",
                    str(TEMPLATE_PATH),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            rendered = output.read_text(encoding="utf-8")
            self.assertTrue(rendered.startswith("<!doctype html>"))
            self.assertIn(
                "Cache &lt;script&gt;alert(1)&lt;/script&gt; {{literal}}", rendered
            )
            self.assertNotIn("<script>", rendered)
            self.assertNotIn("{{BODY}}", rendered)
            self.assertIn('name="viewport"', rendered)
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o600)

    def test_advance_uses_trusted_git_range_and_mismatch_changes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            subprocess.run(
                ["git", "init", "-b", "main", str(repo)],
                check=True,
                capture_output=True,
            )
            git_env = {
                **os.environ,
                "GIT_AUTHOR_NAME": "Andrew Gazelka",
                "GIT_AUTHOR_EMAIL": "andrew@example.com",
                "GIT_COMMITTER_NAME": "Andrew Gazelka",
                "GIT_COMMITTER_EMAIL": "andrew@example.com",
            }
            shas = []
            for index, subject in enumerate(("base", "cache consumer canary (#12)")):
                (repo / f"f{index}").write_text(subject, encoding="utf-8")
                subprocess.run(
                    ["git", "-C", str(repo), "add", "."], check=True, env=git_env
                )
                subprocess.run(
                    ["git", "-C", str(repo), "commit", "-m", subject],
                    check=True,
                    env=git_env,
                    capture_output=True,
                )
                shas.append(
                    subprocess.run(
                        ["git", "-C", str(repo), "rev-parse", "HEAD"],
                        check=True,
                        text=True,
                        capture_output=True,
                    ).stdout.strip()
                )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "update-ref",
                    "refs/remotes/origin/main",
                    shas[1],
                ],
                check=True,
            )

            data = self.fixture()
            data["date"] = (
                datetime.now(timezone.utc).astimezone(PACIFIC).date().isoformat()
            )
            data["repo"] = "example/repo"
            data["range"].update(
                {
                    "from_sha": shas[0],
                    "to_sha": shas[1],
                    "commit_count": 1,
                    "merged_pr_count": 1,
                }
            )
            data["workstreams"] = [data["workstreams"][0]]
            data["workstreams"][0]["prs"] = [{"number": 12, "title": "canary"}]
            data["watchlist"] = []
            content = root / "content.json"
            output = root / "brief.html"
            state = root / "state.json"
            initial_state = (
                json.dumps({"last_sha": shas[0], "last_date": "yesterday"}) + "\n"
            )
            state.write_text(initial_state, encoding="utf-8")
            content.write_text(json.dumps(data), encoding="utf-8")
            command = [
                sys.executable,
                str(RENDER_PATH),
                "--input",
                str(content),
                "--output",
                str(output),
                "--template",
                str(TEMPLATE_PATH),
                "--state",
                str(state),
                "--advance",
            ]
            render_env = {
                **os.environ,
                "IX_CHECKOUT": str(repo),
                "IX_REPO_SLUG": "example/repo",
            }
            proc = subprocess.run(
                command, env=render_env, text=True, capture_output=True, check=False
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            saved = json.loads(state.read_text(encoding="utf-8"))
            self.assertEqual(saved["last_sha"], shas[1])
            self.assertEqual(saved["last_date"], data["date"])

            state.write_text(initial_state, encoding="utf-8")
            data["range"]["to_sha"] = "0" * 40
            content.write_text(json.dumps(data), encoding="utf-8")
            failed_output = root / "must-not-exist.html"
            failed_command = command.copy()
            failed_command[failed_command.index(str(output))] = str(failed_output)
            failed = subprocess.run(
                failed_command,
                env=render_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("trusted range verification failed", failed.stderr)
            self.assertEqual(state.read_text(encoding="utf-8"), initial_state)
            self.assertFalse(failed_output.exists())


class GatherIntegrationTests(unittest.TestCase):
    def test_subprocess_timeout_becomes_collection_error(self):
        with self.assertRaisesRegex(RuntimeError, "timed out"):
            gather.run(["sh", "-c", "sleep 1"], timeout=0.01)

    def test_only_merge_convention_subjects_become_prs(self):
        self.assertIsNone(gather.extract_merged_pr("fix issue #99"))
        self.assertIsNone(gather.extract_merged_pr("docs: mention (#99) later"))
        self.assertEqual(gather.extract_merged_pr("cache consumer canary (#12)"), 12)
        self.assertEqual(
            gather.extract_merged_pr("Merge pull request #13 from ix/topic"), 13
        )

    def test_delta_uses_state_and_degrades_when_gh_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            origin = root / "origin.git"
            checkout = root / "checkout"
            subprocess.run(
                ["git", "init", "--bare", "-b", "main", str(origin)],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "init", "-b", "main", str(checkout)],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "-C", str(checkout), "remote", "add", "origin", str(origin)],
                check=True,
            )
            env = {
                **os.environ,
                "GIT_AUTHOR_NAME": "Andrew Gazelka",
                "GIT_AUTHOR_EMAIL": "andrew@example.com",
                "GIT_COMMITTER_NAME": "Andrew Gazelka",
                "GIT_COMMITTER_EMAIL": "andrew@example.com",
            }
            shas = []
            for index, subject in enumerate(
                ("base", "cache consumer canary (#12)", "vm restore index (#13)")
            ):
                (checkout / f"f{index}").write_text(subject, encoding="utf-8")
                subprocess.run(
                    ["git", "-C", str(checkout), "add", "."], check=True, env=env
                )
                subprocess.run(
                    ["git", "-C", str(checkout), "commit", "-m", subject],
                    check=True,
                    env=env,
                    capture_output=True,
                )
                sha = subprocess.run(
                    ["git", "-C", str(checkout), "rev-parse", "HEAD"],
                    check=True,
                    text=True,
                    capture_output=True,
                ).stdout.strip()
                shas.append(sha)
            subprocess.run(
                ["git", "-C", str(checkout), "push", "origin", "main"],
                check=True,
                capture_output=True,
            )

            loops = root / "loops"
            state = loops / "ix-morning-brief" / "state.json"
            state.parent.mkdir(parents=True)
            state.write_text(
                json.dumps({"last_sha": shas[0], "last_date": "2026-08-04"}),
                encoding="utf-8",
            )
            fake_gh = root / "gh-fail"
            fake_gh.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            fake_gh.chmod(0o700)
            proc = subprocess.run(
                [sys.executable, str(GATHER_PATH)],
                env={
                    **os.environ,
                    "IX_CHECKOUT": str(checkout),
                    "LOOPS_DIR": str(loops),
                    "IX_BRIEF_FORCE": "1",
                    "GH_BIN": str(fake_gh),
                },
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)
            payload = json.loads(proc.stdout)
            self.assertTrue(payload["wakeAgent"])
            self.assertEqual(payload["brief"]["from_sha"], shas[0])
            self.assertEqual(payload["brief"]["to_sha"], shas[2])
            self.assertEqual(payload["brief"]["commit_count"], 2)
            self.assertEqual(payload["brief"]["merged_pr_count"], 2)
            self.assertEqual(
                [pr["number"] for pr in payload["brief"]["merged_prs"]], [12, 13]
            )
            self.assertTrue(payload["brief"]["collection_errors"])
            self.assertEqual(
                json.loads(state.read_text(encoding="utf-8"))["last_sha"], shas[0]
            )

            state.write_text(
                json.dumps({"last_sha": shas[2], "last_date": "2026-08-04"}),
                encoding="utf-8",
            )
            repeat = subprocess.run(
                [sys.executable, str(GATHER_PATH)],
                env={
                    **os.environ,
                    "IX_CHECKOUT": str(checkout),
                    "LOOPS_DIR": str(loops),
                    "IX_BRIEF_FORCE": "1",
                    "GH_BIN": str(fake_gh),
                },
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            self.assertEqual(repeat.returncode, 0, repeat.stderr + repeat.stdout)
            self.assertFalse(json.loads(repeat.stdout)["wakeAgent"])
            self.assertEqual(json.loads(repeat.stdout)["reason"], "no new commits")


if __name__ == "__main__":
    unittest.main()
