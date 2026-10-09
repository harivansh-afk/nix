import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "proxy", Path(__file__).with_name("claude-proxy.py")
)
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)
UPSTREAM, SETTINGS = sys.argv[1:3]
sys.argv = sys.argv[:1]


class ProxyTests(unittest.TestCase):
    def test_sigterm_reaches_child_and_preserves_signal_exit_status(self):
        import signal

        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "ready"
            child_code = f"import os,time; from pathlib import Path; Path({str(ready)!r}).write_text(str(os.getpid())); time.sleep(30)"
            script = Path(__file__).with_name("claude-proxy.py")
            parent_code = (
                "import importlib.util,sys; "
                f"spec=importlib.util.spec_from_file_location('proxy', {str(script)!r}); "
                "proxy=importlib.util.module_from_spec(spec); spec.loader.exec_module(proxy); "
                f"sys.exit(proxy.run_child([sys.executable, '-c', {child_code!r}]))"
            )
            process = subprocess.Popen([sys.executable, "-c", parent_code])
            try:
                for _ in range(100):
                    if ready.exists():
                        break
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), "child did not start")
                process.send_signal(signal.SIGTERM)
                self.assertEqual(process.wait(timeout=5), 143)
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(ready.read_text()), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_usage_failure_json_has_nonzero_status_and_no_secrets(self):
        import io

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / "accounts").mkdir()
            (state / "accounts/a.json").write_text(
                json.dumps(
                    {"type": "claude", "email": "a", "access_token": "secret-token"}
                )
            )
            with (
                patch.object(proxy, "fetch_usage", side_effect=OSError("secret-token")),
                patch("sys.stdout", new_callable=io.StringIO) as output,
            ):
                code = proxy.main(
                    ["--host", "local", "--state-dir", str(state), "usage", "--json"]
                )
            self.assertEqual(code, 1)
            report = json.loads(output.getvalue())
            self.assertEqual(report["accounts"][0]["state"], "unknown")
            self.assertNotIn("secret-token", output.getvalue())

    def test_usage_windows_are_allowlisted_and_unknown_is_not_zero(self):
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(
            {
                "five_hour": {
                    "utilization": 100,
                    "resets_at": "2099-01-01T00:00:00Z",
                    "secret": "never",
                },
                "seven_day": {"utilization": None, "resets_at": None},
                "seven_day_opus": None,
                "seven_day_breakdown": {"rows": [{"private": "never"}]},
                "extra_usage": {"is_enabled": False, "private": "never"},
                "access_token": "never",
            }
        ).encode()
        with patch.object(proxy.urllib.request, "urlopen", return_value=response):
            usage = proxy.fetch_usage({"access_token": "private-token"})
        self.assertEqual(usage["windows"]["five_hour"]["used_percent"], 100)
        self.assertIsNone(usage["windows"]["seven_day"]["used_percent"])
        self.assertNotIn("never", json.dumps(usage))
        self.assertNotIn("seven_day_breakdown", usage["windows"])

    def test_usage_cache_failure_retains_stale_data_and_throttles_retries(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            record = {"access_token": "private-token"}
            good = {
                "windows": {"five_hour": {"used_percent": 42, "resets_at": None}},
                "extra_usage_enabled": False,
            }
            with patch.object(proxy, "fetch_usage", return_value=good) as fetch:
                first = proxy.usage_for(state, "account", record)
                self.assertEqual(first, proxy.usage_for(state, "account", record))
                self.assertEqual(fetch.call_count, 1)
            with patch.object(
                proxy, "fetch_usage", side_effect=OSError("private-token")
            ) as fetch:
                stale = proxy.usage_for(state, "account", record, refresh=True)
                again = proxy.usage_for(state, "account", record)
                self.assertEqual(fetch.call_count, 1)
                self.assertEqual(stale, again)
                self.assertTrue(stale["stale"])
                self.assertEqual(stale["windows"]["five_hour"]["used_percent"], 42)
                self.assertNotIn("private-token", json.dumps(stale))
            for path in (state / "usage").iterdir():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertNotIn("private-token", path.read_text())
            self.assertEqual((state / "usage").stat().st_mode & 0o777, 0o700)
            with patch.object(proxy, "fetch_usage", return_value=good) as fetch:
                proxy.usage_for(state, "account", {"access_token": "refreshed-token"})
                self.assertEqual(fetch.call_count, 1)

    def test_account_status_distinguishes_global_and_model_cooldowns(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            auth = state / "accounts"
            auth.mkdir()
            for name in ("global", "model", "expired", "disabled"):
                (auth / f"{name}.json").write_text(
                    json.dumps(
                        {
                            "type": "claude",
                            "email": name,
                            "disabled": name == "disabled",
                            "access_token": "secret",
                        }
                    )
                )
            (auth / "state.cds").write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "auth_id": "global.json",
                                "reason": "credential_quota",
                                "next_retry_after": "2099-01-01T00:00:00Z",
                            },
                            {
                                "auth_id": "model.json",
                                "model": "opus",
                                "reason": "quota",
                                "next_retry_after": "2099-01-01T00:00:00Z",
                            },
                            {
                                "auth_id": "expired.json",
                                "next_retry_after": "2000-01-01T00:00:00Z",
                            },
                        ]
                    }
                )
            )
            usage = {
                "windows": {
                    "five_hour": {
                        "used_percent": 27,
                        "resets_at": "2099-01-01T00:00:00Z",
                    }
                },
                "extra_usage_enabled": False,
            }
            usage["windows"]["seven_day"] = {
                "used_percent": 10,
                "resets_at": "2099-01-01T00:00:00Z",
            }
            with patch.object(proxy, "fetch_usage", return_value=usage):
                report = proxy.account_report(state)
            states = {a["email"]: a["state"] for a in report["accounts"]}
            self.assertEqual(
                states,
                {
                    "global": "cooling",
                    "model": "limited",
                    "expired": "eligible",
                    "disabled": "disabled",
                },
            )
            self.assertNotIn("secret", json.dumps(report))
            with patch.object(
                proxy,
                "fetch_usage",
                return_value={
                    **usage,
                    "windows": {
                        "five_hour": {
                            "used_percent": 100,
                            "resets_at": "2099-01-01T00:00:00Z",
                        }
                    },
                },
            ):
                report = proxy.account_report(state, refresh=True)
            self.assertEqual(
                next(a for a in report["accounts"] if a["email"] == "expired")["state"],
                "exhausted",
            )

    def test_cli_read_only_empty_state_and_exit_codes(self):
        import io

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "missing"
            args = ["--host", "local", "--state-dir", str(state)]
            with patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(proxy.main([*args, "ls", "--json"]), 0)
                self.assertEqual(json.loads(output.getvalue())["accounts"], [])
            self.assertFalse(state.exists())
            with patch("sys.stdout", new_callable=io.StringIO) as output:
                self.assertEqual(proxy.main([*args, "status", "--json"]), 1)
                self.assertFalse(json.loads(output.getvalue())["running"])
            with patch.object(proxy, "remote", return_value=23) as remote:
                self.assertEqual(
                    proxy.main(
                        [
                            "--host",
                            "spark",
                            "claude",
                            "--resume",
                            "a b",
                            "--model",
                            "opus",
                        ]
                    ),
                    23,
                )
                self.assertEqual(
                    remote.call_args.args[:2],
                    ("spark", ["--resume", "a b", "--model", "opus"]),
                )
            self.assertEqual(proxy.child_status(-15), 143)
            self.assertEqual(proxy.child_status(17), 17)

    def test_remote_command_quotes_arguments_and_forwards_login_callback(self):
        import shlex

        with patch.object(proxy.os, "execvp") as execute:
            proxy.remote_command(
                "spark", "usage", ["--json"], Path("/tmp/state with spaces; no")
            )
            command = execute.call_args.args[1]
            self.assertEqual(
                shlex.split(command[-1]),
                [
                    "cbridge",
                    "--host",
                    "local",
                    "--state-dir",
                    "/tmp/state with spaces; no",
                    "usage",
                    "--json",
                ],
            )
            proxy.remote_command("spark", "login", [])
            command = execute.call_args.args[1]
            self.assertIn("127.0.0.1:54545:127.0.0.1:54545", command)
            self.assertIn("-t", command)
        for host in ("-bad", "bad host", "bad\nhost"):
            with self.assertRaises(ValueError):
                proxy.remote_command(host, "ls", [])

    def test_ascii_output_unknown_stale_and_terminal_control_characters(self):
        import io

        report = {
            "warnings": [],
            "accounts": [
                {
                    "email": "account\x1b[2J",
                    "state": "unknown",
                    "cooldowns": [],
                    "usage": {
                        "stale": True,
                        "error": "Unavailable",
                        "windows": {
                            "five_hour": {"used_percent": 100, "resets_at": None}
                        },
                    },
                }
            ],
        }
        with patch("sys.stdout", new_callable=io.StringIO) as output:
            proxy.render_accounts(report)
        text = output.getvalue()
        self.assertIn("[####################] 100% used (stale)", text)
        self.assertIn("[????????????????????] unknown", text)
        self.assertNotIn("\x1b", text)

    def test_remote_tunnel_cleanup_and_private_credential_delivery(self):
        with (
            patch.object(proxy.subprocess, "run") as run,
            patch.object(
                proxy.subprocess, "check_output", return_value="private-key\n"
            ),
            patch.object(proxy, "run_child", return_value=17) as client,
            patch.object(proxy, "request_models"),
        ):
            self.assertEqual(proxy.remote("spark", ["--", "--resume"]), 17)
            self.assertEqual(client.call_args.args[0], ["claude", "--resume"])
            self.assertEqual(
                client.call_args.kwargs["env"]["ANTHROPIC_AUTH_TOKEN"], "private-key"
            )
            self.assertNotIn("private-key", str(run.call_args_list))
            self.assertIn("exit", run.call_args.args[0])
        with (
            patch.object(proxy.subprocess, "run") as run,
            patch.object(
                proxy.subprocess, "check_output", side_effect=OSError("SSH failed")
            ),
        ):
            with self.assertRaises(OSError):
                proxy.remote("spark", [])
            self.assertIn("exit", run.call_args.args[0])

    def test_private_state_survives_configuration_updates(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            with patch.object(proxy, "SETTINGS", Path(SETTINGS)):
                config, path, key = proxy.prepare(state)
                credential = state / "accounts" / "test.json"
                credential.write_text(
                    json.dumps(
                        {
                            "type": "claude",
                            "email": "test@example.invalid",
                            "access_token": "secret-token",
                            "refresh_token": "secret-refresh",
                        }
                    )
                )
                path.write_text("{}")
                _, _, same_key = proxy.prepare(state)
            self.assertEqual(key, same_key)
            self.assertEqual(json.loads(path.read_text()), config)
            self.assertEqual(state.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual((state / "client-key").stat().st_mode & 0o777, 0o600)
            self.assertEqual(
                json.loads(credential.read_text())["access_token"], "secret-token"
            )
            with patch.object(proxy, "fetch_usage", side_effect=OSError("unavailable")):
                self.assertNotIn(
                    "secret-token", json.dumps(proxy.account_report(state))
                )
            with patch.dict(
                os.environ,
                {
                    "ANTHROPIC_API_KEY": "unrelated-key",
                    "CLAUDE_CODE_OAUTH_TOKEN": "unrelated-login",
                    "CLAUDE_CODE_USE_BEDROCK": "1",
                },
            ):
                environment = proxy.client_environment("http://127.0.0.1:18473", key)
            self.assertNotIn("ANTHROPIC_API_KEY", environment)
            self.assertNotIn("CLAUDE_CODE_OAUTH_TOKEN", environment)
            self.assertNotIn("CLAUDE_CODE_USE_BEDROCK", environment)
            self.assertEqual(environment["ANTHROPIC_AUTH_TOKEN"], key)

    def test_authenticated_sticky_routing_and_quota_failover(self):
        calls = []
        blocked = set()

        class Upstream(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                key = self.headers.get("x-api-key") or self.headers.get(
                    "Authorization", ""
                ).removeprefix("Bearer ")
                calls.append((key, body))
                if key in blocked:
                    self.send_response(429)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Retry-After", "60")
                    self.end_headers()
                    self.wfile.write(
                        b'{"type":"error","error":{"type":"rate_limit_error","message":"quota exhausted"}}'
                    )
                    return
                if body.get("stream"):
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.end_headers()
                    events = [
                        (
                            "message_start",
                            {
                                "message": {
                                    "id": "msg_stream",
                                    "type": "message",
                                    "role": "assistant",
                                    "model": body["model"],
                                    "content": [],
                                    "usage": {"input_tokens": 1, "output_tokens": 0},
                                }
                            },
                        ),
                        (
                            "content_block_start",
                            {"index": 0, "content_block": {"type": "text", "text": ""}},
                        ),
                        (
                            "content_block_delta",
                            {"index": 0, "delta": {"type": "text_delta", "text": key}},
                        ),
                    ]
                    if body["messages"][0]["content"] == "partial":
                        events.append(
                            (
                                "error",
                                {
                                    "error": {
                                        "type": "overloaded_error",
                                        "message": "interrupted after output",
                                    }
                                },
                            )
                        )
                    else:
                        events += [
                            ("content_block_stop", {"index": 0}),
                            (
                                "message_delta",
                                {
                                    "delta": {
                                        "stop_reason": "end_turn",
                                        "stop_sequence": None,
                                    },
                                    "usage": {"output_tokens": 1},
                                },
                            ),
                            ("message_stop", {}),
                        ]
                    for kind, event in events:
                        event["type"] = kind
                        self.wfile.write(
                            f"event: {kind}\ndata: {json.dumps(event)}\n\n".encode()
                        )
                        self.wfile.flush()
                    return
                response = {
                    "id": "msg_test",
                    "type": "message",
                    "role": "assistant",
                    "model": body["model"],
                    "content": [{"type": "text", "text": key}],
                    "stop_reason": "end_turn",
                    "stop_sequence": None,
                    "usage": {"input_tokens": 1, "output_tokens": 1},
                }
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

        server = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            config = json.loads(Path(SETTINGS).read_text())
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            config["server"]["port"] = port
            config["access"] = {"api-keys": ["local-test-key"]}
            config["oauth"] = {"auth-dir": str(state / "accounts")}
            config["api-keys"] = {
                "claude": [
                    {
                        "name": "test",
                        "base-url": f"http://127.0.0.1:{server.server_port}",
                        "keys": [{"api-key": "account-a"}, {"api-key": "account-b"}],
                        "models": [{"name": "claude-sonnet-4-5-20250929"}],
                    }
                ]
            }
            config_path = state / "config.json"
            config_path.write_text(json.dumps(config))
            with (state / "log").open("w+") as log:
                process = subprocess.Popen(
                    [UPSTREAM, "-config", str(config_path), "-local-model"],
                    cwd=state,
                    stdout=log,
                    stderr=log,
                )
                try:
                    url = f"http://127.0.0.1:{port}"
                    for _ in range(100):
                        try:
                            proxy.request_models(url, "local-test-key")
                            break
                        except OSError:
                            if process.poll() is not None:
                                log.seek(0)
                                self.fail(log.read())
                            time.sleep(0.1)
                    else:
                        self.fail("Proxy did not start")
                    with self.assertRaises(urllib.error.HTTPError) as unauthenticated:
                        proxy.request_models(url, "wrong-key")
                    self.assertEqual(unauthenticated.exception.code, 401)
                    with self.assertRaises(urllib.error.HTTPError) as management:
                        urllib.request.urlopen(url + "/v8/management/config", timeout=5)
                    self.assertEqual(management.exception.code, 404)

                    def turn(session, prompt, stream=False):
                        request = urllib.request.Request(
                            url + "/v1/messages",
                            data=json.dumps(
                                {
                                    "model": "claude-sonnet-4-5-20250929",
                                    "max_tokens": 8,
                                    "stream": stream,
                                    "system": [
                                        {
                                            "type": "text",
                                            "text": "Stable prefix",
                                            "cache_control": {"type": "ephemeral"},
                                        }
                                    ],
                                    "messages": [{"role": "user", "content": prompt}],
                                }
                            ).encode(),
                            headers={
                                "Authorization": "Bearer local-test-key",
                                "Content-Type": "application/json",
                                "anthropic-version": "2023-06-01",
                                "x-claude-code-session-id": session,
                            },
                        )
                        with urllib.request.urlopen(request, timeout=15) as response:
                            if stream:
                                return response.read().decode()
                            return json.load(response)["content"][0]["text"]

                    first = turn("session-one", "First conversation")
                    second = turn("session-two", "Independent conversation")
                    self.assertNotEqual(first, second)
                    self.assertEqual(
                        turn("session-one", "Next turn with changed content"), first
                    )
                    self.assertEqual(turn("session-two", "Its next turn"), second)
                    self.assertEqual(
                        calls[-1][1]["system"][0]["cache_control"],
                        {"type": "ephemeral"},
                    )
                    blocked.add(first)
                    self.assertEqual(
                        turn("session-one", "Account quota rejected"), second
                    )
                    blocked.clear()
                    self.assertEqual(
                        turn("session-one", "Keep recovered assignment"), second
                    )
                    streamed = turn("session-one", "stream", stream=True)
                    self.assertIn("message_stop", streamed)
                    self.assertIn(second, streamed)
                    before = len(calls)
                    interrupted = turn("session-one", "partial", stream=True)
                    self.assertIn("content_block_delta", interrupted)
                    self.assertIn("error", interrupted)
                    self.assertEqual(len(calls), before + 1)
                finally:
                    process.terminate()
                    process.wait(timeout=10)


unittest.main()
