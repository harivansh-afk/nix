import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    "computer", Path(__file__).with_name("computer.py")
)
computer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(computer)


def result(stdout="", code=0):
    return subprocess.CompletedProcess([], code, stdout, "")


class ComputerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.workspace = self.root / "project with spaces"
        self.workspace.mkdir()
        self.env = patch.dict(os.environ, {"XDG_STATE_HOME": str(self.root / "state")})
        self.env.start()
        self.settings = patch.dict(
            computer.SETTINGS,
            {
                "podman": "podman",
                "git": "git",
                "cua": "cua",
                "image": "image@sha256:pinned",
                "ssh": "ssh",
                "ssh_config": "/store/config",
            },
            clear=True,
        )
        self.settings.start()
        self.output = contextlib.ExitStack()
        self.output.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.output.enter_context(contextlib.redirect_stderr(io.StringIO()))
        self.addCleanup(self.output.close)
        self.addCleanup(self.settings.stop)
        self.addCleanup(self.env.stop)
        self.addCleanup(self.tmp.cleanup)

    def test_name_validation(self):
        for name in ("../escape", "/tmp/foo", "a/b", "", "A", "x" * 41, "a;id"):
            with self.subTest(name=name), self.assertRaises(computer.Error):
                computer.task_dir(name)
        self.assertEqual(computer.task_dir("task-1").name, "task-1")

    def test_home_and_ancestors_are_not_project_mounts(self):
        home = Path.home().resolve()
        for path in (home, *home.parents):
            with self.subTest(path=path), self.assertRaises(computer.Error):
                computer.validate_workspace(path)
        computer.validate_workspace(self.workspace)

    def test_command_errors_redact_credentials(self):
        failed = subprocess.CompletedProcess([], 1, "", "bad bearer synthetic-secret")
        with (
            patch.object(computer.subprocess, "run", return_value=failed),
            self.assertRaises(computer.Error) as error,
        ):
            computer.command(
                ["cua", "spaces"], env={"CUA_ENV_TOKEN": "synthetic-secret"}
            )
        self.assertNotIn("synthetic-secret", str(error.exception))
        self.assertIn("[redacted]", str(error.exception))

    def test_exclusive_lease_and_stable_lock_inode(self):
        folder = computer.task_dir("task")
        with computer.lease(folder):
            inode = (folder / "lock").stat().st_ino
            with self.assertRaises(computer.Error), computer.lease(folder):
                self.fail("a second session acquired the desktop")
        with computer.lease(folder):
            self.assertEqual((folder / "lock").stat().st_ino, inode)
        self.assertEqual(stat.S_IMODE(folder.stat().st_mode), 0o700)

    def test_codex_arguments_and_generated_name(self):
        with patch.object(computer, "run", return_value=17) as run:
            self.assertEqual(
                computer.main(["--name", "review", "--", "resume", "--last"]), 17
            )
            run.assert_called_with("review", ["resume", "--last"])
        with patch.object(computer, "run", return_value=0) as run:
            computer.main(["exec", "inspect the UI"])
            name, args = run.call_args.args
            self.assertTrue(computer.NAME.fullmatch(name))
            self.assertEqual(args, ["exec", "inspect the UI"])

    def test_launch_does_not_change_caller_file_creation_mask(self):
        previous = os.umask(0o022)
        try:
            with patch.object(computer, "run", return_value=0):
                computer.main(["--name", "task"])
            self.assertEqual(os.umask(0o022), 0o022)
            secret = self.root / "private"
            computer.write_private(secret, "synthetic-secret")
            self.assertEqual(stat.S_IMODE(secret.stat().st_mode), 0o600)
        finally:
            os.umask(previous)

    def test_explicit_directory_becomes_absolute_and_literal_prompt_is_untouched(self):
        directory, args = computer.requested_directory(
            ["-C", str(self.workspace), "exec", "--", "-Cnot-an-option"]
        )
        self.assertEqual(directory, self.workspace)
        self.assertEqual(args[-1], "-Cnot-an-option")
        self.assertEqual(args[1], str(self.workspace))
        with self.assertRaises(computer.Error):
            computer.requested_directory(["--cd"])

    def test_codex_shim_keeps_devin_routing_and_scopes_only_desktop(self):
        env = {
            "COM_COMPUTER_CODEX": "/bin/codex",
            "COM_COMPUTER_URL": "http://127.0.0.1:45678/mcp",
            "COM_COMPUTER_TOKEN": "synthetic-private-token",
            "COM_COMPUTER_SESSION": "task:123",
        }
        original = [
            "--profile",
            "devin-codex",
            "-c",
            'model_provider="devin"',
            "exec",
            "task",
        ]
        with patch.dict(os.environ, env), patch.object(computer.os, "execv") as execute:
            computer.codex_shim(original)
            executable, argv = execute.call_args.args
            self.assertEqual(executable, "/bin/codex")
            self.assertEqual(argv[-len(original) :], original)
            self.assertIn("--no-daemon", argv)
            self.assertIn("mcp_servers.computer.enabled=false", argv)
            self.assertIn(
                'mcp_servers.task_computer.url="http://127.0.0.1:45678/mcp"', argv
            )
            self.assertIn(
                'mcp_servers.task_computer.http_headers.X-Cua-Agent-Session="task:123"',
                argv,
            )
            self.assertNotIn(env["COM_COMPUTER_TOKEN"], " ".join(argv))
            execute.reset_mock()
            computer.codex_shim(["debug", "models", "--bundled"])
            execute.assert_called_with(
                "/bin/codex", ["/bin/codex", "debug", "models", "--bundled"]
            )

    def test_existing_com_trust_rule_handles_git_worktrees(self):
        subprocess.run(["git", "init", "-q", str(self.workspace)], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.workspace),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "--allow-empty",
                "-qm",
                "fixture",
            ],
            check=True,
        )
        worktree = self.root / "worktree"
        subprocess.run(
            [
                "git",
                "-C",
                str(self.workspace),
                "worktree",
                "add",
                "-qb",
                "test",
                str(worktree),
            ],
            check=True,
        )
        self.assertEqual(computer.trust_target(worktree), self.workspace)

    def test_launcher_finds_its_packaged_shim_without_path_entry(self):
        package = self.root / "package"
        here = package / "lib/com-computer"
        here.mkdir(parents=True)
        shim = package / "bin/com-computer-codex"
        shim.parent.mkdir()
        shim.touch()
        child = MagicMock()
        child.wait.return_value = 17
        child.poll.return_value = 17
        with (
            patch.object(computer, "HERE", here),
            patch.object(
                computer.shutil,
                "which",
                side_effect=lambda name: {
                    "codex": "/host/codex",
                    "devin-codex": "/host/devin-codex",
                }.get(name),
            ),
            patch.object(computer.subprocess, "Popen", return_value=child) as spawn,
            patch.object(computer, "trust_target", return_value=self.workspace),
        ):
            status = computer.launch_agent(
                {"name": "task", "port": 45678, "token": "synthetic-secret"},
                self.workspace,
                ["resume", "--last"],
            )
        self.assertEqual(status, 17)
        argv = spawn.call_args.args[0]
        self.assertEqual(argv[argv.index("--codex") + 1], str(shim))
        self.assertEqual(argv[-3:], ["--", "resume", "--last"])
        self.assertNotIn("synthetic-secret", " ".join(argv))
        self.assertEqual(
            spawn.call_args.kwargs["env"]["COM_COMPUTER_CODEX"], "/host/codex"
        )

    def test_foreign_container_is_not_adopted(self):
        with (
            patch.object(
                computer,
                "podman",
                return_value=result(json.dumps([{"Config": {"Labels": {}}}])),
            ),
            self.assertRaises(computer.Error),
        ):
            computer.inspect("task")

    def fake_lifecycle(self):
        box = {"data": None, "calls": []}

        def podman(*args, **kwargs):
            box["calls"].append(args)
            if args[0] == "create":
                box["data"] = {
                    "Id": "owned-id",
                    "State": {"Running": False, "Paused": False, "Status": "created"},
                    "NetworkSettings": {
                        "Ports": {
                            "3211/tcp": [{"HostIp": "127.0.0.1", "HostPort": "45678"}]
                        }
                    },
                }
                return result("owned-id\n")
            if args[0] == "start":
                box["data"]["State"].update(Running=True, Status="running")
            if args[0] == "stop":
                box["data"]["State"].update(Running=False, Status="exited")
            if args[0] == "rm":
                box["data"] = None
            return result()

        stack = contextlib.ExitStack()
        stack.enter_context(patch.object(computer, "require_linux"))
        stack.enter_context(patch.object(computer, "podman", side_effect=podman))
        stack.enter_context(
            patch.object(computer, "inspect", side_effect=lambda name: box["data"])
        )
        stack.enter_context(patch.object(computer, "ready"))
        stack.enter_context(
            patch.object(computer.Path, "cwd", return_value=self.workspace)
        )
        self.addCleanup(stack.close)
        return box

    def test_lifecycle_resume_credentials_ports_mounts_and_exit_status(self):
        box = self.fake_lifecycle()
        with patch.object(computer, "launch_agent", return_value=17):
            self.assertEqual(computer.run("task", []), 17)
        folder = computer.task_dir("task")
        token = (folder / "token").read_text()
        self.assertEqual(stat.S_IMODE((folder / "token").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((folder / "desktop.json").stat().st_mode), 0o600)
        create = box["calls"][0]
        self.assertIn("127.0.0.1::3211", create)
        self.assertIn("keep-id:uid=1000,gid=1000", create)
        self.assertIn("pasta:--map-host-loopback,169.254.1.3", create)
        self.assertIn("host.containers.internal:169.254.1.3", create)
        self.assertIn(str(self.workspace) + ":/workspace:rw", create)
        self.assertNotIn(token, " ".join(create))
        self.assertFalse(box["data"]["State"]["Running"])
        with patch.object(computer, "launch_agent", return_value=0):
            computer.run("task", ["resume", "--last"])
        self.assertEqual(sum(call[0] == "create" for call in box["calls"]), 1)
        self.assertEqual((folder / "token").read_text(), token)
        self.assertEqual(sum(call[0] == "stop" for call in box["calls"]), 2)
        inode = (folder / "lock").stat().st_ino
        computer.delete("task")
        self.assertFalse((folder / "token").exists())
        self.assertEqual((folder / "lock").stat().st_ino, inode)
        self.assertTrue(self.workspace.is_dir())

    def test_launch_failure_stops_desktop_and_keeps_state(self):
        box = self.fake_lifecycle()
        with (
            patch.object(
                computer, "launch_agent", side_effect=computer.Error("launch failed")
            ),
            self.assertRaises(computer.Error),
        ):
            computer.run("task", [])
        self.assertFalse(box["data"]["State"]["Running"])
        self.assertTrue((computer.task_dir("task") / "desktop.json").exists())

    def test_resume_rejects_changed_identity_or_project(self):
        box = self.fake_lifecycle()
        with patch.object(computer, "launch_agent", return_value=0):
            computer.run("task", [])
        box["data"]["Id"] = "replacement"
        with self.assertRaises(computer.Error):
            computer.run("task", [])
        box["data"]["Id"] = "owned-id"
        with self.assertRaises(computer.Error):
            computer.run("task", ["-C", str(self.root)])

    def test_connection_rejects_public_binding(self):
        box = self.fake_lifecycle()
        with patch.object(computer, "launch_agent", return_value=0):
            computer.run("task", [])
        box["data"]["State"]["Running"] = True
        box["data"]["NetworkSettings"]["Ports"]["3211/tcp"][0]["HostIp"] = "0.0.0.0"
        with self.assertRaises(computer.Error):
            computer.connection("task")
        with self.assertRaises(computer.Error):
            computer.delete("task")

    def test_orphan_stop_preserves_state_and_refuses_active_owner(self):
        box = self.fake_lifecycle()
        with patch.object(computer, "launch_agent", return_value=0):
            computer.run("task", [])
        box["data"]["State"]["Running"] = True
        with (
            computer.lease(computer.task_dir("task")),
            self.assertRaises(computer.Error),
        ):
            computer.stop("task")
        self.assertTrue(box["data"]["State"]["Running"])
        computer.stop("task")
        self.assertFalse(box["data"]["State"]["Running"])
        self.assertTrue((computer.task_dir("task") / "token").exists())

    def test_mac_view_keeps_token_out_of_arguments_and_reuses_local_port(self):
        app = self.root / "Cua Spaces.app"
        helper = app / "Contents/MacOS/cua"
        helper.parent.mkdir(parents=True)
        helper.touch()
        calls = []
        info = {"name": "task", "port": 45678, "token": "synthetic-secret"}

        def execute(args, **kwargs):
            calls.append((args, kwargs))
            return result(code=1 if "check" in args else 0)

        with (
            patch.object(computer.sys, "platform", "darwin"),
            patch.object(computer, "APP", app),
            patch.object(computer.Path, "home", return_value=self.root),
            patch.object(computer, "remote", return_value=result(json.dumps(info))),
            patch.object(computer, "command", side_effect=execute),
        ):
            computer.view("task")
            first = json.loads(
                (computer.state_root() / "viewers/task/tunnel.json").read_text()
            )
            computer.view("task")
            second = json.loads(
                (computer.state_root() / "viewers/task/tunnel.json").read_text()
            )
        self.assertEqual(first["local_port"], second["local_port"])
        self.assertNotIn(info["token"], str([args for args, _ in calls]))
        registrations = [kw for args, kw in calls if "add" in args]
        self.assertEqual(registrations[0]["env"]["CUA_ENV_TOKEN"], info["token"])


if __name__ == "__main__":
    unittest.main()
