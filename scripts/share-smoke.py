"""Exercise the packaged CLI against an isolated real Quantum server."""

import argparse
import importlib.util
import json
import os
import secrets
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def run(server_binary, cli):
    with tempfile.TemporaryDirectory(prefix="quantum-smoke-") as directory:
        root = Path(directory)
        source = root / "source"
        source.mkdir()
        uploads = root / "uploads"
        uploads.mkdir()
        note = source / "notes + space.md"
        note.write_text("# Original\n")
        (source / "sibling.txt").write_text("PRIVATE SIBLING")
        (source / ".secret").write_text("PRIVATE HIDDEN")
        folder = source / "folder"
        folder.mkdir()
        (folder / "visible.txt").write_text("visible")
        (folder / "escape.txt").symlink_to(source / "sibling.txt")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        origin = f"http://127.0.0.1:{port}"
        password = secrets.token_urlsafe(32)
        (root / "password").write_text(password)
        (root / "password").chmod(0o600)
        config = root / "config.yaml"
        config.write_text(f"""server:
  listen: 127.0.0.1
  port: {port}
  database: {json.dumps(str(root / "database.db"))}
  cacheDir: {json.dumps(str(root / "cache"))}
  externalUrl: {origin}
  disableUpdateCheck: true
  sources:
    - name: Test
      path: {json.dumps(str(source))}
      config:
        defaultEnabled: true
        rules:
          - ignoreSymlinks: true
          - ignoreHidden: true
    - name: Uploads
      path: {json.dumps(str(uploads))}
      config:
        defaultEnabled: true
auth:
  adminUsername: test-owner
  methods:
    password:
      enabled: true
      signup: false
""")
        env = os.environ | {
            "FILEBROWSER_ADMIN_PASSWORD": password,
            "SHARE_SERVER": origin,
            "SHARE_PASSWORD_FILE": str(root / "password"),
            "SHARE_USER": "test-owner",
        }
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def request(path, method="GET", body=None, headers=None):
            req = urllib.request.Request(
                origin + path, data=body, method=method, headers=headers or {}
            )
            try:
                with opener.open(req, timeout=5) as response:
                    return response.status, response.read()
            except urllib.error.HTTPError as exc:
                return exc.code, exc.read()

        def command(*args, success=True):
            result = subprocess.run(
                [cli, *map(str, args)],
                env=env,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            assert (result.returncode == 0) == success, result.stderr
            return result.stdout.strip()

        def public(key, path="/", method="GET", body=None, raw=True):
            route = "/public/api/raw" if raw else "/public/api/resources"
            query = urllib.parse.urlencode({"hash": key, "path": path, "file": path})
            return request(route + "?" + query, method, body)

        def create(path, *flags):
            return command(path, *flags).rsplit("/", 1)[-1]

        with (root / "server.log").open("w") as log:
            process = subprocess.Popen(
                [server_binary, "-c", str(config)], env=env, stdout=log, stderr=log
            )
            try:
                for _ in range(60):
                    if process.poll() is not None:
                        raise AssertionError(
                            "Quantum exited: " + (root / "server.log").read_text()
                        )
                    try:
                        if request("/health")[0] == 200:
                            break
                    except (urllib.error.URLError, TimeoutError):
                        pass
                    time.sleep(0.1)
                else:
                    raise AssertionError("Quantum did not become ready")
                read = create(note)
                edit = create(note, "--edit", "--expires", "7d")
                assert public(read) == (200, b"# Original\n")
                assert public(read, method="PUT", body=b"bad", raw=False)[0] == 403
                assert (
                    public(edit, method="PUT", body=b"# Browser\n", raw=False)[0] == 200
                )
                assert note.read_text() == "# Browser\n"
                replacement = source / "replacement.tmp"
                replacement.write_text("# Atomic local save\n")
                replacement.replace(note)
                assert public(read) == (200, b"# Atomic local save\n")
                assert public(read, "/../sibling.txt")[0] in (400, 403, 404, 500)
                assert public(read, "/sibling.txt")[0] in (400, 403, 404, 500)
                assert request("/api/resources?source=Test&path=/")[0] == 401
                directory_share = create(folder)
                assert public(directory_share, "/visible.txt") == (200, b"visible")
                assert public(directory_share, "/escape.txt")[0] in (400, 403, 404, 500)
                assert public(edit, method="DELETE", raw=False)[0] == 403
                copied = create(note, "--copy")
                note.write_text("# Later original\n")
                assert public(copied) == (200, b"# Atomic local save\n")
                command(source / ".secret", success=False)
                command(folder / "escape.txt", success=False)
                command(root / "password", success=False)
                assert read in command("list")
                command("revoke", origin + "/public/share/" + read)
                assert public(read)[0] in (401, 403, 404, 500)

                spec = importlib.util.spec_from_file_location(
                    "share", Path(__file__).parents[1] / "pkgs/scripts/lib/share.py"
                )
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                os.environ.update(
                    {
                        key: value
                        for key, value in env.items()
                        if key.startswith("SHARE_")
                    }
                )
                client = module.Client()
                protected = client.request(
                    "/api/share",
                    "POST",
                    body={
                        "source": "Test",
                        "path": "/notes + space.md",
                        "shareType": "normal",
                        "password": "test-link-password",
                    },
                )
                assert public(protected["hash"])[0] in (401, 403)
                assert request(
                    "/public/api/raw?"
                    + urllib.parse.urlencode(
                        {
                            "hash": protected["hash"],
                            "file": "/",
                            "token": protected["token"],
                        }
                    )
                ) == (200, b"# Later original\n")
                expiring = client.request(
                    "/api/share",
                    "POST",
                    body={
                        "source": "Test",
                        "path": "/notes + space.md",
                        "shareType": "normal",
                        "expires": "1",
                        "unit": "seconds",
                    },
                )
                time.sleep(2)
                assert public(expiring["hash"])[0] in (401, 403, 404)
                print(
                    "PASS: live reads, anonymous edit, read-only/delete denial, atomic saves, sibling/symlink confinement, private inventory, copies, password, expiry, list and revoke"
                )
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("server_binary")
    parser.add_argument("cli")
    args = parser.parse_args()
    run(args.server_binary, args.cli)
