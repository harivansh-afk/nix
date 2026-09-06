"""Trusted launcher: resolve OAuth, then give an isolated worker one access token."""

import json
import subprocess
import sys


def main():
    config = json.load(open(sys.argv[1]))
    payload = json.loads(sys.stdin.read(65537))
    if not isinstance(payload.get("text"), str) or len(payload["text"]) > 4000:
        raise ValueError("Invalid TV request")
    history = payload.get("history", [])
    if not isinstance(history, list) or len(history) > 20:
        raise ValueError("Invalid history")
    for item in history:
        if item.get("role") not in {"user", "assistant"} or not isinstance(
            item.get("content"), str
        ):
            raise ValueError("Invalid history message")
    from hermes_cli.runtime_provider import resolve_runtime_provider

    runtime = resolve_runtime_provider(
        requested="openai-codex", target_model=config["model"]
    )
    request = {
        "text": payload["text"],
        "history": history,
        "model": config["model"],
        "runtime": {
            key: runtime[key] for key in ("api_key", "base_url", "provider", "api_mode")
        },
        "check": payload.get("check") is True,
    }
    argv = [
        config["bwrap"],
        "--die-with-parent",
        "--new-session",
        "--unshare-user",
        "--unshare-pid",
        "--unshare-ipc",
        "--unshare-uts",
        "--cap-drop",
        "ALL",
        "--clearenv",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--tmpfs",
        "/tmp",
        "--dir",
        "/state",
        "--dir",
        "/state/.hermes",
    ]
    mounts = {
        "/nix/store": "/nix/store",
        config["workerConfig"]: "/state/.hermes/config.yaml",
        config["instructions"]: "/instructions.md",
        "/run/roomcast": "/run/roomcast",
        "/etc/ssl/certs/ca-certificates.crt": "/etc/ssl/certs/ca-certificates.crt",
        "/etc/resolv.conf": "/etc/resolv.conf",
        "/etc/hosts": "/etc/hosts",
    }
    for source, target in mounts.items():
        argv.extend(["--ro-bind", source, target])
    environment = {
        "HOME": "/state",
        "HERMES_HOME": "/state/.hermes",
        "PATH": config["path"],
        "SSL_CERT_FILE": "/etc/ssl/certs/ca-certificates.crt",
        "PYTHONUNBUFFERED": "1",
    }
    for key, value in environment.items():
        argv.extend(["--setenv", key, value])
    argv.extend(["--chdir", "/state", config["python"], config["worker"]])
    # The caller kills the whole process group on timeout, including MCP children.
    result = subprocess.run(
        argv,
        input=json.dumps(request),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=170,
    )
    if result.returncode:
        if payload.get("check") is True:
            print(
                result.stderr.replace(runtime["api_key"], "[redacted]")[-4000:],
                file=sys.stderr,
            )
        # Never forward SDK errors or stderr, which can contain credentials or media URLs.
        print(json.dumps({"error": "TV worker failed; check the service locally."}))
        return
    lines = result.stdout.strip().splitlines()
    answer = json.loads(lines[-1]) if lines else {}
    if not (isinstance(answer.get("reply"), str) or payload.get("check")):
        raise ValueError("Invalid worker response")
    print(json.dumps(answer))


if __name__ == "__main__":
    main()
