import argparse
import fcntl
import json
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

UPSTREAM = "@upstream@"
SETTINGS = Path("@settings@")


def prepare(state):
    os.umask(0o077)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    auth = state / "accounts"
    auth.mkdir(exist_ok=True, mode=0o700)
    auth.chmod(0o700)
    with (state / "setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        key_path = state / "client-key"
        if not key_path.exists():
            with key_path.open("x") as output:
                output.write(secrets.token_urlsafe(32) + "\n")
        key_path.chmod(0o600)
        key = key_path.read_text().strip()
        if not key:
            raise ValueError(f"Empty client key: {key_path}")
        config = json.loads(SETTINGS.read_text())
        config["access"] = {"api-keys": [key]}
        config["oauth"] = {"auth-dir": str(auth)}
        rendered = json.dumps(config, indent=2) + "\n"
        config_path = state / "config.json"
        if not config_path.exists() or config_path.read_text() != rendered:
            with tempfile.NamedTemporaryFile(
                mode="w", dir=state, delete=False
            ) as output:
                output.write(rendered)
                temporary = output.name
            os.replace(temporary, config_path)
        config_path.chmod(0o600)
    return config, config_path, key


def accounts(state):
    result = []
    for path in sorted((state / "accounts").glob("*.json")):
        try:
            record = json.loads(path.read_text())
        except (ValueError, OSError):
            continue
        if record.get("type") != "claude":
            continue
        result.append(
            {
                "email": record.get("email", "unknown"),
                "disabled": bool(record.get("disabled", False)),
            }
        )
    return result


def request_models(url, key):
    request = urllib.request.Request(
        url + "/v1/models", headers={"Authorization": "Bearer " + key}
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=5) as response:
        return json.load(response)


def client_environment(url, key):
    environment = os.environ.copy()
    for name in (
        "ANTHROPIC_API_KEY",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "ANTHROPIC_PROFILE",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY",
        "CLAUDE_CODE_USE_AWS",
    ):
        environment.pop(name, None)
    environment.update(
        {
            "ANTHROPIC_BASE_URL": url,
            "ANTHROPIC_AUTH_TOKEN": key,
            "CLAUDE_CODE_GATEWAY_HINT_HEADERS": "1",
        }
    )
    return environment


def remote(host, arguments):
    if not host or host.startswith("-"):
        raise ValueError("Expected an SSH host name")
    with tempfile.TemporaryDirectory(prefix="claude-proxy-") as directory:
        control_socket = str(Path(directory) / "ssh")
        ssh = ["ssh", "-S", control_socket]
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        subprocess.run(
            [
                *ssh,
                "-M",
                "-fNT",
                "-o",
                "ControlPersist=no",
                "-o",
                "ExitOnForwardFailure=yes",
                "-o",
                "ConnectTimeout=10",
                "-L",
                f"127.0.0.1:{port}:127.0.0.1:18473",
                host,
            ],
            check=True,
        )
        try:
            key = subprocess.check_output(
                [*ssh, host, "claude-proxy", "key"], text=True
            ).strip()
            url = f"http://127.0.0.1:{port}"
            request_models(url, key)
            arguments = arguments[1:] if arguments[:1] == ["--"] else arguments
            return subprocess.call(
                ["claude", *arguments], env=client_environment(url, key)
            )
        finally:
            subprocess.run(
                [*ssh, "-O", "exit", host],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )


def main():
    parser = argparse.ArgumentParser(description="Private two-account Claude gateway")
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=Path(
            os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
        )
        / "claude-proxy",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("serve", "login", "status", "models", "key"):
        commands.add_parser(name)
    client = commands.add_parser(
        "claude", help="Run installed Claude Code through the proxy"
    )
    client.add_argument("args", nargs=argparse.REMAINDER)
    remote_client = commands.add_parser(
        "remote", help="Run local Claude Code through an SSH host"
    )
    remote_client.add_argument("host")
    remote_client.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command == "remote":
        return remote(args.host, args.args)
    state = args.state_dir.expanduser().resolve()
    config, config_path, key = prepare(state)
    url = f"http://127.0.0.1:{config['server']['port']}"
    if args.command == "key":
        print(key)
    elif args.command == "status":
        report = {"url": url, "state": str(state), "accounts": accounts(state)}
        try:
            models = request_models(url, key)
            report.update(running=True, model_count=len(models.get("data", [])))
        except (OSError, ValueError):
            report.update(running=False)
        print(json.dumps(report, indent=2))
    elif args.command == "models":
        print(json.dumps(request_models(url, key), indent=2))
    elif args.command == "claude":
        request_models(url, key)
        arguments = args.args[1:] if args.args[:1] == ["--"] else args.args
        os.execvpe("claude", ["claude", *arguments], client_environment(url, key))
    else:
        os.chdir(state)
        command = [UPSTREAM, "-config", str(config_path), "-local-model"]
        if args.command == "login":
            print(
                "Sign in to one Max account. Run login again for the second account.",
                flush=True,
            )
            print(
                "From a Mac browser, forward localhost:54545 to this host over SSH.",
                flush=True,
            )
            command += ["-claude-login", "-no-browser"]
        environment = {
            name: value
            for name, value in os.environ.items()
            if name.upper() not in {"MANAGEMENT_PASSWORD", "HOME_JWT", "DEPLOY"}
            and not name.upper().startswith(("PGSTORE_", "GITSTORE_", "OBJECTSTORE_"))
        }
        os.execve(UPSTREAM, command, environment)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except (
        OSError,
        ValueError,
        urllib.error.URLError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"claude-proxy: {error}", file=sys.stderr)
        sys.exit(1)
