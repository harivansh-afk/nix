import argparse
import fcntl
import hashlib
import json
import math
import os
import secrets
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
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


def remote(host, arguments, state_dir=None):
    def terminate(signum, frame):
        raise SystemExit(128 + signum)

    previous = signal.signal(signal.SIGTERM, terminate)
    try:
        return remote_session(host, arguments, state_dir)
    finally:
        signal.signal(signal.SIGTERM, previous)


def remote_session(host, arguments, state_dir=None):
    validate_host(host)
    with tempfile.TemporaryDirectory(prefix="claude-proxy-") as directory:
        control_socket = str(Path(directory) / "ssh")
        ssh = ["ssh", "-S", control_socket]
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        try:
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
            key_command = ["env", "CBRIDGE_HOST=local", "claude-proxy"]
            if state_dir is not None:
                key_command += ["--state-dir", str(state_dir)]
            key_command += ["key"]
            key = subprocess.check_output(
                [*ssh, host, shlex.join(key_command)], text=True
            ).strip()
            url = f"http://127.0.0.1:{port}"
            request_models(url, key)
            arguments = arguments[1:] if arguments[:1] == ["--"] else arguments
            return run_child(["claude", *arguments], env=client_environment(url, key))
        finally:
            subprocess.run(
                [*ssh, "-O", "exit", host],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )


def timestamp(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def clean_text(value):
    return "".join(c if c.isprintable() else "?" for c in str(value))


def format_time(value):
    seconds = timestamp(value)
    if seconds is None:
        return "unknown"
    return datetime.fromtimestamp(seconds).astimezone().strftime("%b %d %H:%M:%S %Z")


def fetch_usage(record):
    token = record.get("access_token")
    if not token:
        raise ValueError("No access token; run cbridge login")
    request = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": "Bearer " + token,
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        data = json.load(response)
    if not isinstance(data, dict):
        raise TypeError("Invalid usage response")
    windows = {}
    for name, window in data.items():
        if name != "five_hour" and not name.startswith("seven_day"):
            continue
        if not isinstance(window, dict) or "utilization" not in window:
            continue
        percent = window.get("utilization")
        if (
            isinstance(percent, bool)
            or not isinstance(percent, (int, float))
            or not math.isfinite(percent)
            or percent < 0
        ):
            percent = None
        reset = window.get("resets_at")
        windows[name] = {
            "used_percent": percent,
            "resets_at": reset if timestamp(reset) is not None else None,
        }
    if not windows:
        raise ValueError("Usage response contains no quota windows")
    extra = data.get("extra_usage")
    return {
        "windows": windows,
        "extra_usage_enabled": extra.get("is_enabled")
        if isinstance(extra, dict)
        else None,
    }


def usage_for(state, account_id, record, refresh=False):
    # Serialize readers so watch/multiple terminals do not stampede the endpoint.
    cache_dir = state / "usage"
    cache_dir.mkdir(mode=0o700, exist_ok=True)
    cache_dir.chmod(0o700)
    cache_id = hashlib.sha256(account_id.encode()).hexdigest()
    cache_path = cache_dir / (cache_id + ".json")
    fingerprint = hashlib.sha256(
        str(record.get("access_token", "")).encode()
    ).hexdigest()
    with open(cache_dir / (cache_id + ".lock"), "a", opener=private_open) as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cached = {}
        try:
            cached = json.loads(cache_path.read_text())
            if not isinstance(cached, dict) or cached.get("fingerprint") != fingerprint:
                cached = {}
        except (OSError, ValueError):
            pass
        now = time.time()
        age = now - (timestamp(cached.get("attempted_at")) or 0)
        if refresh or not 0 <= age < 60:
            checked_at = datetime.now(timezone.utc).isoformat()
            try:
                cached = {
                    **fetch_usage(record),
                    "checked_at": checked_at,
                    "error": None,
                    "stale": False,
                }
            except (OSError, ValueError, TypeError) as error:
                if isinstance(error, urllib.error.HTTPError):
                    message = f"Usage endpoint returned HTTP {error.code}"
                    if error.code == 401:
                        message += "; credential may need refreshing or cbridge login"
                else:
                    # Never echo an upstream body or exception containing credentials.
                    message = "Could not retrieve usage (network or invalid response)"
                cached.update(error=message, stale=bool(cached.get("windows")))
            cached.update(attempted_at=checked_at, fingerprint=fingerprint)
            with tempfile.NamedTemporaryFile(
                mode="w", dir=cache_dir, delete=False
            ) as output:
                json.dump(cached, output)
                temporary = output.name
            os.replace(temporary, cache_path)
        return {k: v for k, v in cached.items() if k != "fingerprint"}


def private_open(path, flags):
    return os.open(path, flags, 0o600)


def account_report(state, refresh=False):
    cooldowns = {}
    warnings = []
    now = time.time()
    for path in sorted((state / "accounts").glob("*.cds")):
        try:
            data = json.loads(path.read_text())
            for entry in data["records"]:
                until = entry.get("next_retry_after")
                if (timestamp(until) or 0) <= now:
                    continue
                cooldowns.setdefault(
                    entry.get("auth_id", data.get("auth_id")), []
                ).append(
                    {
                        "model": entry.get("model"),
                        "reason": entry.get("reason", "cooldown"),
                        "retry_at": until,
                    }
                )
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            warnings.append(
                "Could not read a cooldown record; availability may be incomplete"
            )
    result = []
    for path in sorted((state / "accounts").glob("*.json")):
        try:
            record = json.loads(path.read_text())
            if not isinstance(record, dict):
                raise TypeError("Invalid account")
        except (OSError, ValueError, TypeError):
            warnings.append("Could not read an account record")
            continue
        if record.get("type") != "claude":
            continue
        disabled = bool(record.get("disabled", False))
        usage = usage_for(state, path.name, record, refresh) if not disabled else None
        cooling = cooldowns.get(path.name, [])
        credential_cooling = any(c["model"] is None for c in cooling)
        exhausted = bool(
            usage
            and not usage.get("stale")
            and any(
                w["used_percent"] is not None
                and w["used_percent"] >= 100
                and (timestamp(w["resets_at"]) or 0) > now
                for name, w in usage.get("windows", {}).items()
                if name in ("five_hour", "seven_day")
            )
        )
        if disabled:
            status = "disabled"
        elif credential_cooling:
            status = "cooling"
        elif exhausted and usage.get("extra_usage_enabled") is not True:
            status = "exhausted"
        elif (
            not usage
            or usage.get("error")
            or warnings
            or any(
                usage.get("windows", {}).get(name, {}).get("used_percent") is None
                for name in ("five_hour", "seven_day")
            )
        ):
            status = "unknown"
        elif cooling:
            status = "limited"
        else:
            status = "eligible"
        result.append(
            {
                "id": path.name,
                "email": record.get("email", "unknown"),
                "state": status,
                "disabled": disabled,
                "cooldowns": cooling,
                "usage": usage,
            }
        )
    return {"accounts": result, "warnings": sorted(set(warnings))}


def render_accounts(report, detailed=False):
    if not report["accounts"]:
        print("No Claude accounts. Run cbridge login to add one.")
    for account in report["accounts"]:
        print(f"{clean_text(account['email'])}  {account['state']}")
        usage = account["usage"] or {}
        windows = usage.get("windows", {})
        labels = {"five_hour": "5-hour", "seven_day": "Weekly"}
        for name in ("five_hour", "seven_day", *sorted(set(windows) - set(labels))):
            if name not in labels and not detailed:
                continue
            window = windows.get(name, {})
            percent = window.get("used_percent")
            label = labels.get(name, name.removeprefix("seven_day_").replace("_", " "))
            if percent is None:
                print(f"  {clean_text(label):12} [????????????????????] unknown")
                continue
            filled = min(20, max(0, int(percent / 5 + 0.5)))
            bar = "#" * filled + "-" * (20 - filled)
            suffix = " (stale)" if usage.get("stale") else ""
            print(f"  {clean_text(label):12} [{bar}] {percent:g}% used{suffix}")
            print(f"  {'':12} Resets {format_time(window.get('resets_at'))}")
        if usage.get("error"):
            print(f"  Usage unavailable: {clean_text(usage['error'])}")
        if usage.get("checked_at"):
            print(f"  Usage checked {format_time(usage['checked_at'])}")
        if detailed:
            extra = usage.get("extra_usage_enabled")
            print(
                f"  Extra usage: {'enabled' if extra is True else 'disabled' if extra is False else 'unknown'}"
            )
        for cooldown in account["cooldowns"]:
            model = clean_text(cooldown["model"] or "All models")
            print(
                f"  {model}: {clean_text(cooldown['reason'])}; retry {format_time(cooldown['retry_at'])}"
            )
        print()
    counts = {}
    for account in report["accounts"]:
        counts[account["state"]] = counts.get(account["state"], 0) + 1
    summary = ", ".join(f"{count} {state}" for state, count in sorted(counts.items()))
    print(
        f"Pool: {len(report['accounts'])} account(s)"
        + (f", {summary}" if summary else "")
    )
    print("Eligible means no known quota block; request success is not guaranteed.")
    for warning in report["warnings"]:
        print(f"cbridge: {warning}", file=sys.stderr)


def validate_host(host):
    if (
        not host
        or host.startswith("-")
        or any(c.isspace() or ord(c) < 32 for c in host)
    ):
        raise ValueError("Expected an SSH host name")


def child_status(code):
    return code if code >= 0 else 128 - code


def run_child(command, **kwargs):
    process = subprocess.Popen(command, **kwargs)
    previous = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGTERM, lambda signum, frame: process.send_signal(signum))
    try:
        return child_status(process.wait())
    except KeyboardInterrupt:
        process.send_signal(signal.SIGINT)
        process.wait()
        return 130
    finally:
        signal.signal(signal.SIGTERM, previous)


def remote_command(host, command, arguments, state_dir=None):
    validate_host(host)
    remote_args = ["cbridge", "--host", "local"]
    if state_dir is not None:
        remote_args += ["--state-dir", str(state_dir)]
    remote_args += [command, *arguments]
    ssh = ["ssh", "-o", "ConnectTimeout=10"]
    if command == "login":
        ssh += [
            "-t",
            "-o",
            "ExitOnForwardFailure=yes",
            "-L",
            "127.0.0.1:54545:127.0.0.1:54545",
        ]
    os.execvp("ssh", [*ssh, host, shlex.join(remote_args)])


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="cbridge",
        description="Claude account gateway. Global options go before the command.",
        epilog="Commands: claude (launch), ls (accounts), usage (all windows), status "
        "(gateway health), models, login, serve, key. Use COMMAND --help for options. "
        "Mac defaults to Spark; --host local selects this machine. cc is a shell alias.",
    )
    parser.add_argument(
        "--host",
        help="SSH host or local (also CBRIDGE_HOST)",
    )
    parser.add_argument(
        "--state-dir", type=Path, help="State directory on the selected host"
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=(
            "claude",
            "ls",
            "usage",
            "status",
            "models",
            "login",
            "serve",
            "key",
            "remote",
        ),
    )
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        return 0
    if args.command == "remote":
        if not args.arguments:
            parser.error("remote requires an SSH host")
        return remote(args.arguments[0], args.arguments[1:], args.state_dir)
    if args.command == "serve":
        if args.host not in (None, "local"):
            parser.error("serve runs locally; start the service on the target host")
        args.host = "local"
    elif args.host is None:
        args.host = os.environ.get(
            "CBRIDGE_HOST", "spark" if sys.platform == "darwin" else "local"
        )
    options = argparse.ArgumentParser(prog=f"cbridge {args.command}")
    if args.command in ("ls", "usage", "status", "models"):
        options.add_argument(
            "--json", action="store_true", help="Print structured JSON"
        )
    if args.command in ("ls", "usage", "status"):
        options.add_argument(
            "--refresh", action="store_true", help="Bypass the 60-second usage cache"
        )
    if args.command != "claude":
        flags = options.parse_args(args.arguments)
    if args.host != "local":
        if args.command == "claude":
            return remote(args.host, args.arguments, args.state_dir)
        return remote_command(args.host, args.command, args.arguments, args.state_dir)
    state = (
        (
            args.state_dir
            or Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
            / "claude-proxy"
        )
        .expanduser()
        .resolve()
    )
    if args.command in ("serve", "login"):
        config, config_path, key = prepare(state)
        os.chdir(state)
        command = [UPSTREAM, "-config", str(config_path), "-local-model"]
        if args.command == "login":
            print(
                "Sign in to a Claude account. Repeat login to add another account.",
                file=sys.stderr,
                flush=True,
            )
            print(
                "For a remote browser, forward localhost:54545 over SSH (cbridge --host HOST login does this).",
                file=sys.stderr,
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
        return 0
    if args.command in ("ls", "usage", "status"):
        report = account_report(state, flags.refresh)
        failed = bool(report["warnings"]) or any(
            a["state"] == "unknown" or (a["usage"] and a["usage"].get("error"))
            for a in report["accounts"]
        )
        if args.command == "status":
            report.update(running=False, url=None)
            try:
                config = json.loads((state / "config.json").read_text())
                report["url"] = f"http://127.0.0.1:{config['server']['port']}"
                models = request_models(
                    report["url"], (state / "client-key").read_text().strip()
                )
                report.update(running=True, model_count=len(models.get("data", [])))
            except (OSError, ValueError, KeyError):
                pass
            failed = failed or not report["running"]
        if flags.json:
            print(json.dumps(report, indent=2))
        else:
            if args.command == "status":
                print(
                    f"Gateway: {'running' if report['running'] else 'unreachable'} ({report['url'] or 'not configured'})\n"
                )
            render_accounts(report, detailed=args.command == "usage")
        return int(failed)
    key = (state / "client-key").read_text().strip()
    if args.command == "key":
        print(key)
        return 0
    config = json.loads((state / "config.json").read_text())
    url = f"http://127.0.0.1:{config['server']['port']}"
    models = request_models(url, key)
    if args.command == "models":
        if flags.json:
            print(json.dumps(models, indent=2))
        else:
            for model in models.get("data", []):
                print(clean_text(model["id"]))
    elif args.command == "claude":
        arguments = (
            args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        )
        os.execvpe("claude", ["claude", *arguments], client_environment(url, key))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"cbridge: {error}", file=sys.stderr)
        sys.exit(1)
