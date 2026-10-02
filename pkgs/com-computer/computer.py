"""Own one persistent desktop for one invocation of the existing com launcher."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SETTINGS = (
    json.loads((HERE / "settings.json").read_text())
    if (HERE / "settings.json").exists()
    else {}
)
LABEL = "sh.harivan.com-computer"
APP = Path("/Applications/Cua Spaces.app")
NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,39}\Z")


class Error(Exception):
    pass


def command(args, *, env=None, timeout=60, check=True):
    result = subprocess.run(
        args, env=env, text=True, capture_output=True, timeout=timeout, check=False
    )
    if check and result.returncode:
        detail = result.stderr.strip()
        for key, value in (env or {}).items():
            if value and any(
                word in key.upper() for word in ("TOKEN", "SECRET", "KEY")
            ):
                detail = detail.replace(value, "[redacted]")
        raise Error(
            f"{Path(args[0]).name} {args[1]} failed (exit {result.returncode}): {detail[-1000:]}"
        )
    return result


def state_root():
    root = (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "com-computer"
    )
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    return root


def task_dir(name):
    if not NAME.fullmatch(name):
        raise Error("Use a desktop name of 1–40 lowercase letters, digits or hyphens.")
    return state_root() / name


def write_private(path, text):
    with open(path, "w", opener=lambda p, f: os.open(p, f, 0o600)) as out:
        os.fchmod(out.fileno(), 0o600)
        out.write(text)


def write_json(path, data):
    tmp = path.with_suffix(".tmp")
    write_private(tmp, json.dumps(data) + "\n")
    tmp.replace(path)


@contextlib.contextmanager
def lease(folder):
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    with open(folder / "lock", "a", opener=lambda p, f: os.open(p, f, 0o600)) as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Error(
                "That desktop already belongs to another running com-computer session."
            ) from None
        yield


def podman(*args, check=True, timeout=60):
    return command([SETTINGS["podman"], *args], check=check, timeout=timeout)


def inspect(name):
    result = podman("container", "inspect", "com-computer-" + name, check=False)
    if result.returncode:
        return None
    data = json.loads(result.stdout)[0]
    if data.get("Config", {}).get("Labels", {}).get(LABEL) != name:
        raise Error(
            "Container name is occupied by a container this launcher does not own."
        )
    return data


def require_linux():
    if sys.platform != "linux":
        raise Error(
            "Run com-computer on Spark. On your Mac, use: com-computer view NAME"
        )
    info = json.loads(podman("info", "--format", "json").stdout)
    if not info.get("host", {}).get("security", {}).get("rootless"):
        raise Error("com-computer requires rootless Podman.")


def environment(token):
    return dict(os.environ, CUA_ENV_TOKEN=token, DO_NOT_TRACK="1", CUA_TELEMETRY="0")


def connection(name):
    folder = task_dir(name)
    metadata = json.loads((folder / "desktop.json").read_text())
    data = inspect(name)
    if not data or not data["State"]["Running"] or data["State"].get("Paused"):
        raise Error("That desktop is stopped. Start it with com-computer first.")
    if data["Id"] != metadata["container_id"]:
        raise Error(
            "Container identity changed; refusing to use the saved credentials."
        )
    binding = data["NetworkSettings"]["Ports"]["3211/tcp"][0]
    if binding["HostIp"] != "127.0.0.1":
        raise Error("The desktop is not bound exclusively to loopback.")
    return {
        "name": name,
        "port": int(binding["HostPort"]),
        "token": (folder / "token").read_text().strip(),
    }


def ready(info, timeout=90):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        try:
            result = command(
                [
                    SETTINGS["cua"],
                    "spacesd",
                    "caps",
                    f"http://127.0.0.1:{info['port']}",
                    "--json",
                ],
                env=environment(info["token"]),
                timeout=5,
                check=False,
            )
            if result.returncode == 0:
                caps = json.loads(result.stdout)
                features = {
                    f["name"] for f in caps.get("features", []) if f.get("supported")
                }
                if caps.get("displays") and {"desktop_stream", "driver"} <= features:
                    return
        except (subprocess.TimeoutExpired, json.JSONDecodeError):
            pass
        time.sleep(0.5)
    raise Error("The desktop did not become ready within 90 seconds.")


def trust_target(workspace):
    result = command(
        [
            SETTINGS["git"],
            "-C",
            str(workspace),
            "rev-parse",
            "--path-format=absolute",
            "--git-common-dir",
        ],
        check=False,
    )
    return (
        Path(result.stdout.strip()).parent.resolve()
        if result.returncode == 0
        else workspace
    )


def launch_agent(info, workspace, args):
    devin = shutil.which("devin-codex")
    codex = shutil.which("codex")
    if not devin or not codex:
        raise Error(
            "Install/sign in to Codex and Devin as for the existing com command."
        )
    shim = HERE.parent.parent / "bin/com-computer-codex"
    if not shim.is_file():
        raise Error("The packaged com-computer-codex helper is missing.")
    env = dict(
        os.environ,
        COM_COMPUTER_URL=f"http://127.0.0.1:{info['port']}/mcp",
        COM_COMPUTER_TOKEN=info["token"],
        COM_COMPUTER_SESSION=info["name"] + ":" + secrets.token_hex(8),
        COM_COMPUTER_CODEX=codex,
    )
    argv = [
        devin,
        "run",
        "--reasoning-effort",
        "medium",
        "--trust-project",
        str(trust_target(workspace)),
        "--codex",
        str(shim),
        "--",
        *args,
    ]
    child = subprocess.Popen(argv, cwd=workspace, env=env)
    previous = {}

    def interrupt(signum, _frame):
        child.send_signal(signum)

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        previous[signum] = signal.signal(signum, interrupt)
    try:
        return child.wait()
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def codex_shim(args):
    real = os.environ.get("COM_COMPUTER_CODEX")
    if not real:
        raise Error("This helper is launched by com-computer.")
    if args[:2] == ["debug", "models"]:
        return os.execv(real, [real, *args])
    config = {
        "mcp_servers.computer.enabled": False,
        "mcp_servers.task_computer.url": os.environ["COM_COMPUTER_URL"],
        "mcp_servers.task_computer.bearer_token_env_var": "COM_COMPUTER_TOKEN",
        "mcp_servers.task_computer.http_headers.X-Cua-Agent-Session": os.environ[
            "COM_COMPUTER_SESSION"
        ],
        "mcp_servers.task_computer.required": True,
        "mcp_servers.task_computer.startup_timeout_sec": 30,
        "mcp_servers.task_computer.tool_timeout_sec": 60,
        "developer_instructions": (HERE / "instructions.md").read_text(),
    }
    flags = [
        part
        for key, value in config.items()
        for part in ("-c", key + "=" + json.dumps(value))
    ]
    # A private Codex process keeps per-session endpoint/token environment separate.
    end = args.index("--") if "--" in args else len(args)
    args = [arg for arg in args[:end] if arg != "--no-daemon"] + args[end:]
    os.execv(real, [real, "--no-daemon", *flags, *args])


def requested_directory(args):
    """Make Codex's explicit working directory stable across a desktop resume."""
    args = list(args)
    directory = None
    for index, arg in enumerate(args):
        if arg == "--":
            break
        if arg in ("-C", "--cd"):
            if index + 1 == len(args):
                raise Error(f"{arg} requires a directory.")
            directory = Path(args[index + 1]).expanduser().resolve()
            args[index + 1] = str(directory)
        elif arg.startswith("--cd="):
            directory = Path(arg.split("=", 1)[1]).expanduser().resolve()
            args[index] = "--cd=" + str(directory)
        elif arg.startswith("-C"):
            directory = Path(arg[2:]).expanduser().resolve()
            args[index] = "-C" + str(directory)
    if directory is not None and not directory.is_dir():
        raise Error("The requested working directory does not exist.")
    return directory, args


def validate_workspace(workspace):
    home = Path.home().resolve()
    if workspace == home or workspace in home.parents:
        raise Error(
            "Choose a project directory with -C; the host home and its ancestors are not shared with desktops."
        )


def run(name, args):
    require_linux()
    requested, args = requested_directory(args)
    folder = task_dir(name)
    with lease(folder):
        metadata_path = folder / "desktop.json"
        data = inspect(name)
        if metadata_path.exists():
            metadata = json.loads(metadata_path.read_text())
            if not data or data["Id"] != metadata["container_id"]:
                raise Error(
                    "Saved desktop is missing or was replaced. Choose a new name or delete this saved record."
                )
            workspace = Path(metadata["workspace"])
            if requested is not None and requested != workspace:
                raise Error(
                    "This desktop belongs to another project directory. Use a different desktop name."
                )
            if not workspace.is_dir():
                raise Error(
                    "The desktop's original project directory no longer exists."
                )
            validate_workspace(workspace)
        else:
            if data:
                raise Error(
                    "A container exists without its saved metadata; refusing to replace it."
                )
            workspace = requested or Path.cwd().resolve()
            validate_workspace(workspace)
            token = secrets.token_hex(32)
            write_private(folder / "token", token)
            env_file = folder / "container.env"
            write_private(
                env_file,
                f"CUA_ENV_TOKEN={token}\nDO_NOT_TRACK=1\nCUA_TELEMETRY=0\nCUA_DRIVER_RS_TELEMETRY_ENABLED=0\n",
            )
            print(
                "Creating desktop; the first run downloads the pinned Linux image.",
                flush=True,
            )
            result = podman(
                "create",
                "--name",
                "com-computer-" + name,
                "--label",
                LABEL + "=" + name,
                "--runtime",
                "crun",
                "--network",
                "pasta:--map-host-loopback,169.254.1.3",
                "--add-host",
                "host.containers.internal:169.254.1.3",
                "--userns",
                "keep-id:uid=1000,gid=1000",
                "--user",
                "0",
                "--cpus",
                "2",
                "--memory",
                "4g",
                "--shm-size",
                "1g",
                "--publish",
                "127.0.0.1::3211",
                "--env-file",
                str(env_file),
                "--volume",
                str(workspace) + ":/workspace:rw",
                SETTINGS["image"],
                timeout=1800,
            )
            metadata = {
                "container_id": result.stdout.strip(),
                "workspace": str(workspace),
                "image": SETTINGS["image"],
                "created_at": int(time.time()),
            }
            write_json(metadata_path, metadata)
        try:
            data = inspect(name)
            if data["State"].get("Paused"):
                podman("unpause", data["Id"])
            elif not data["State"]["Running"]:
                podman("start", data["Id"])
            info = connection(name)
            ready(info)
            print(
                f"Desktop: {name}\nOn your Mac: com-computer view {name}\nReopen later: com-computer --name {name}",
                flush=True,
            )
            return launch_agent(info, workspace, args)
        finally:
            data = inspect(name)
            if data and data["State"]["Running"]:
                if data["State"].get("Paused"):
                    podman("unpause", data["Id"])
                podman("stop", "--time", "10", data["Id"])
            print(
                f"Desktop {name} stopped; files and logins retained. Delete with: com-computer delete {name}",
                file=sys.stderr,
            )


def listing():
    require_linux()
    rows = []
    for path in sorted(state_root().glob("*/desktop.json")):
        if not NAME.fullmatch(path.parent.name):
            continue
        metadata = json.loads(path.read_text())
        data = inspect(path.parent.name)
        rows.append(
            {
                "name": path.parent.name,
                "state": data["State"]["Status"] if data else "missing",
                "workspace": metadata["workspace"],
            }
        )
    return rows


def delete(name):
    require_linux()
    folder = task_dir(name)
    with lease(folder):
        data = inspect(name)
        metadata_path = folder / "desktop.json"
        if not data and not metadata_path.exists():
            raise Error("No desktop with that name exists.")
        if (
            data
            and metadata_path.exists()
            and data["Id"] != json.loads(metadata_path.read_text())["container_id"]
        ):
            raise Error(
                "Container identity changed; refusing to delete the replacement."
            )
        if data:
            if data["State"]["Running"]:
                raise Error(
                    "Desktop is still running. Stop its Codex session before deleting it."
                )
            podman("rm", data["Id"])
        for filename in ("desktop.json", "token", "container.env"):
            (folder / filename).unlink(missing_ok=True)
    # Keep the lock inode, so waiters never acquire a different lock for this name.
    print(f"Deleted desktop {name}. Project files and Codex history are retained.")


def stop(name):
    require_linux()
    folder = task_dir(name)
    with lease(folder):
        data = inspect(name)
        if not data:
            raise Error("No desktop with that name exists.")
        metadata = json.loads((folder / "desktop.json").read_text())
        if data["Id"] != metadata["container_id"]:
            raise Error("Container identity changed; refusing to stop the replacement.")
        if data["State"].get("Paused"):
            podman("unpause", data["Id"])
        if data["State"]["Running"]:
            podman("stop", "--time", "10", data["Id"])
    print(f"Stopped desktop {name}; files and logins retained.")


def remote(args):
    import shlex

    return command(
        [
            SETTINGS["ssh"],
            "-F",
            SETTINGS["ssh_config"],
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "spark",
            shlex.join(["com-computer", *args]),
        ]
    )


def view(name):
    if sys.platform != "darwin":
        raise Error("Run com-computer view NAME on your Mac.")
    task_dir(name)
    helper = APP / "Contents/MacOS/cua"
    if not helper.exists():
        raise Error(
            "Cua Spaces is not installed. Apply the Mac Nix configuration first."
        )
    info = json.loads(remote(["_connection", name]).stdout)
    port = info["port"]
    if not isinstance(port, int) or not 1024 <= port <= 65535:
        raise Error("Spark returned an invalid desktop port.")
    folder = state_root() / "viewers" / name
    with lease(folder):
        metadata_path = folder / "tunnel.json"
        metadata = (
            json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
        )
        sockets = Path.home() / "Library/Caches/com-computer"
        sockets.mkdir(mode=0o700, parents=True, exist_ok=True)
        control = str(
            sockets / (hashlib.sha256(name.encode()).hexdigest()[:16] + ".sock")
        )
        ssh = [SETTINGS["ssh"], "-F", SETTINGS["ssh_config"], "-S", control]
        live = command([*ssh, "-O", "check", "spark"], check=False).returncode == 0
        if live and metadata.get("remote_port") != port:
            command([*ssh, "-O", "exit", "spark"])
            live = False
        local_port = metadata.get("local_port")
        if not local_port:
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                local_port = sock.getsockname()[1]
        if not live:
            command(
                [
                    *ssh,
                    "-M",
                    "-fNT",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ExitOnForwardFailure=yes",
                    "-o",
                    "ControlPersist=600",
                    "-o",
                    "ServerAliveInterval=30",
                    "-o",
                    "ServerAliveCountMax=3",
                    "-o",
                    "ForwardAgent=no",
                    "-L",
                    f"127.0.0.1:{local_port}:127.0.0.1:{port}",
                    "spark",
                ]
            )
            write_json(metadata_path, {"local_port": local_port, "remote_port": port})
        command(
            [
                str(helper),
                "spaces",
                "add",
                f"http://127.0.0.1:{local_port}",
                "--name",
                "com/" + name,
                "--json",
            ],
            env=environment(info["token"]),
        )
        command(["/usr/bin/open", "-a", str(APP)])
    print(
        f"Open com/{name} in Cua Spaces. The desktop keeps running if the viewer closes."
    )


def main(args):
    if args and args[0] == "_codex":
        codex_shim(args[1:])
    if args and args[0] == "_connection":
        if len(args) != 2:
            raise Error("A desktop name is required.")
        require_linux()
        print(json.dumps(connection(args[1])))
        return 0
    if args and args[0] == "list":
        if args not in (["list"], ["list", "--json"]):
            raise Error("Usage: com-computer list [--json]")
        if sys.platform == "darwin":
            rows = json.loads(remote(["list", "--json"]).stdout)
        else:
            rows = listing()
        if "--json" in args:
            print(json.dumps(rows))
        else:
            for row in rows:
                print(f"{row['name']}\t{row['state']}\t{row['workspace']}")
        return 0
    if args and args[0] in ("view", "delete", "stop"):
        if len(args) != 2:
            raise Error(f"Usage: com-computer {args[0]} NAME")
        return {"view": view, "delete": delete, "stop": stop}[args[0]](args[1])
    parser = argparse.ArgumentParser(
        prog="com-computer",
        description="Run com with an isolated desktop on Spark. Use list, view NAME (Mac), stop NAME, or delete NAME. Codex arguments follow --.",
    )
    parser.add_argument(
        "--name", help="reopen a named desktop; otherwise create a new one"
    )
    opts, forwarded = parser.parse_known_args(args)
    forwarded = forwarded[1:] if forwarded[:1] == ["--"] else forwarded
    option_end = forwarded.index("--") if "--" in forwarded else len(forwarded)
    if any(
        arg == "--remote" or arg.startswith("--remote=")
        for arg in forwarded[:option_end]
    ):
        raise Error(
            "A desktop session uses the local Codex process; --remote is not supported."
        )
    name = opts.name
    if not name:
        prefix = (
            re.sub(r"[^a-z0-9]+", "-", Path.cwd().name.lower()).strip("-")[:25]
            or "task"
        )
        name = prefix + "-" + secrets.token_hex(4)
    return run(name, forwarded)


if __name__ == "__main__":

    def cancel(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGHUP, cancel)
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("com-computer: interrupted", file=sys.stderr)
        sys.exit(130)
    except (
        Error,
        FileNotFoundError,
        subprocess.TimeoutExpired,
        json.JSONDecodeError,
    ) as error:
        print(f"com-computer: {error}", file=sys.stderr)
        sys.exit(1)
