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
    def test_remote_tunnel_cleanup_and_private_credential_delivery(self):
        with (
            patch.object(proxy.subprocess, "run") as run,
            patch.object(
                proxy.subprocess, "check_output", return_value="private-key\n"
            ),
            patch.object(proxy.subprocess, "call", return_value=17) as client,
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
            self.assertNotIn("secret-token", json.dumps(proxy.accounts(state)))
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
