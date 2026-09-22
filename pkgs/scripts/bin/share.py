import datetime
import getopt
import getpass
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

HELP = """Usage: share [OPTION]... FILE
  or:  share --list
  or:  share --revoke=ID
Create a link to a file or directory on Spark.

  -c, --copy              copy FILE to Spark before sharing
  -e, --edit              allow editing the shared file
  -l, --list              list shares
  -p, --password          prompt for a link password
  -r, --revoke=ID         revoke a share by ID or URL
  -x, --expires=DURATION  expire after DURATION (e.g., 30m, 2h, 7d, 2w)
  -h, --help              display this help and exit
  -V, --version           output version information and exit

Links are read-only and do not expire unless specified.
Live sharing requires a file in a configured Spark source.
Use --copy for files elsewhere, including on the Mac.
"""


def usage_error(message):
    print(
        f"share: {message}\nTry 'share --help' for more information.", file=sys.stderr
    )
    sys.exit(2)


def parse_args():
    try:
        flags, operands = getopt.gnu_getopt(
            sys.argv[1:],
            "cehlpr:Vx:",
            [
                "copy",
                "edit",
                "help",
                "list",
                "password",
                "revoke=",
                "version",
                "expires=",
            ],
        )
    except getopt.GetoptError as exc:
        option = ("-" if len(exc.opt) == 1 else "--") + exc.opt
        if "not recognized" in exc.msg:
            usage_error(f"unrecognized option '{option}'")
        if "requires argument" in exc.msg:
            usage_error(f"option '{option}' requires an argument")
        usage_error(str(exc))
    options = {
        "copy": False,
        "edit": False,
        "password": False,
        "expires": "",
        "list": False,
        "revoke": None,
    }
    for flag, value in flags:
        if flag in ("-h", "--help"):
            print(HELP, end="")
            sys.exit(0)
        if flag in ("-V", "--version"):
            print("share (FileBrowser Quantum) @VERSION@")
            sys.exit(0)
        name = {
            "-c": "copy",
            "-e": "edit",
            "-l": "list",
            "-p": "password",
            "-r": "revoke",
            "-x": "expires",
        }.get(flag, flag[2:])
        options[name] = value if name in ("revoke", "expires") else True
    if options["list"] and options["revoke"] is not None:
        usage_error("options '--list' and '--revoke' are mutually exclusive")
    managing = options["list"] or options["revoke"] is not None
    if managing and any(
        options[name] for name in ("copy", "edit", "password", "expires")
    ):
        usage_error("sharing options cannot be used with '--list' or '--revoke'")
    if not managing and not operands:
        usage_error("missing file operand")
    if len(operands) > (0 if managing else 1):
        usage_error(f"extra operand '{operands[0 if managing else 1]}'")
    if any(flag in ("-x", "--expires") for flag, _ in flags):
        options["expires"] = expiration(options["expires"])
    return options, operands[0] if operands else None


class ShareError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self):
        credential = Path(
            os.environ.get("SHARE_PASSWORD_FILE", "/run/secrets/filebrowser-password")
        )
        readable_credential = credential.is_file() and os.access(credential, os.R_OK)
        self.ssh_host = os.environ.get("SHARE_SSH_HOST", "spark")
        self.server = os.environ.get(
            "SHARE_SERVER",
            "http://127.0.0.1:39476"
            if readable_credential
            else "https://files.harivan.sh",
        ).rstrip("/")
        parsed = urllib.parse.urlsplit(self.server)
        if (
            (
                parsed.scheme != "https"
                and not (parsed.scheme == "http" and parsed.hostname == "127.0.0.1")
            )
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.path
        ):
            raise ShareError(
                "SHARE_SERVER must be an HTTPS origin or http://127.0.0.1:PORT"
            )
        self.local = parsed.hostname == "127.0.0.1"
        if "SHARE_SERVER" in os.environ and not readable_credential:
            raise ShareError("a custom server requires a readable SHARE_PASSWORD_FILE")
        if readable_credential:
            password = credential.read_text().strip()
        elif "SHARE_PASSWORD_FILE" in os.environ:
            raise ShareError("SHARE_PASSWORD_FILE is not readable")
        else:
            password = subprocess.check_output(
                self.ssh("cat /run/secrets/filebrowser-password"), text=True, timeout=15
            ).strip()
        if not password or "\n" in password or "\r" in password:
            raise ShareError("invalid account credential")
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect()
        )
        self.token = None
        username = os.environ.get("SHARE_USER", "rathi")
        self.token = (
            self.request(
                "/api/auth/login",
                "POST",
                query={"username": username},
                headers={"X-Password": urllib.parse.quote(password, safe="")},
                raw=True,
            )
            .decode()
            .strip()
        )

    def ssh(self, command):
        return [
            "@SSH@",
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "--",
            self.ssh_host,
            command,
        ]

    def request(
        self, path, method="GET", query=None, body=None, headers=None, raw=False
    ):
        url = self.server + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = dict(headers or {})
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        try:
            request = urllib.request.Request(
                url, data=data, headers=headers, method=method
            )
            with self.opener.open(request, timeout=30) as response:
                content = response.read()
        except urllib.error.HTTPError as exc:
            raise ShareError(f"{method} {path}: HTTP {exc.code}") from None
        except urllib.error.URLError as exc:
            raise ShareError(f"cannot reach Quantum: {exc.reason}") from None
        if raw or not content:
            return content
        return json.loads(content)


def expiration(value):
    match = re.fullmatch(r"([1-9][0-9]{0,5})(m|h|d|w)", value)
    if not match:
        usage_error(f"invalid duration '{value}'")
    seconds = int(match[1]) * {"m": 60, "h": 3600, "d": 86400, "w": 604800}[match[2]]
    if seconds > 9_223_372_036:
        usage_error(f"duration out of range: '{value}'")
    return str(seconds)


def share_id(value):
    if "://" in value:
        value = urllib.parse.urlsplit(value).path.rstrip("/").split("/")[-1]
    if not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", value):
        raise ShareError("expected a share ID or its URL")
    return value


def source_for(path, sources):
    matches = []
    for source in sources:
        root = Path(source["path"])
        if path.is_relative_to(root) and not source.get("config", {}).get(
            "disabled", False
        ):
            matches.append((root, source))
    if not matches:
        raise ShareError(f"'{path}': outside configured sources; use --copy")
    root, source = max(matches, key=lambda item: len(item[0].parts))
    relative = path.relative_to(root)
    if any(part.startswith(".") for part in relative.parts):
        raise ShareError("hidden paths are excluded from this instance")
    return source["name"], "/" + relative.as_posix().removeprefix(".")


def copied_file(client, path, sources):
    if (
        not client.local
        and client.server != "https://files.harivan.sh"
        and "SHARE_SSH_HOST" not in os.environ
    ):
        raise ShareError("copying to a custom server requires SHARE_SSH_HOST")
    upload = next((source for source in sources if source["name"] == "Uploads"), None)
    if upload is None:
        raise ShareError("this server has no Uploads source for --copy")
    destination = Path(upload["path"]) / uuid.uuid4().hex

    def archive_filter(member):
        if any(part.startswith(".") for part in Path(member.name).parts[1:]):
            return None
        if not (member.isfile() or member.isdir()):
            raise ShareError("copies cannot contain symlinks or special files")
        return member

    if client.local:
        destination.mkdir(mode=0o700)
        if path.is_file():
            shutil.copy2(path, destination / path.name)
        else:

            def ignored(folder, names):
                for name in names:
                    child = Path(folder) / name
                    if not name.startswith(".") and (
                        child.is_symlink() or not (child.is_file() or child.is_dir())
                    ):
                        raise ShareError(
                            "copies cannot contain symlinks or special files"
                        )
                return [name for name in names if name.startswith(".")]

            shutil.copytree(path, destination / path.name, ignore=ignored)
    else:
        command = f"umask 077; mkdir -- {shlex.quote(str(destination))} && tar --no-same-owner --no-same-permissions -xf - -C {shlex.quote(str(destination))}"
        with subprocess.Popen(client.ssh(command), stdin=subprocess.PIPE) as process:
            try:
                with tarfile.open(
                    fileobj=process.stdin, mode="w|", dereference=False
                ) as archive:
                    archive.add(path, arcname=path.name, filter=archive_filter)
            finally:
                process.stdin.close()
            if process.wait() != 0:
                raise ShareError(
                    "upload failed; an incomplete private copy may remain in Uploads"
                )
    return destination / path.name


def main():
    options, operand = parse_args()
    identifier = share_id(options["revoke"]) if options["revoke"] is not None else None
    path = None
    if operand is not None:
        path = Path(operand).expanduser()
        if path.is_symlink():
            raise ShareError("cannot share a symbolic link")
        path = path.resolve(strict=True)
        if not (path.is_file() or path.is_dir()) or path == Path("/"):
            raise ShareError(
                "source must be a regular file or directory below a configured source"
            )
        if path.name.startswith(".") or any(char in str(path) for char in "\r\n"):
            raise ShareError(
                "hidden paths and paths containing newlines cannot be shared"
            )
    password = None
    if options["password"]:
        password = getpass.getpass("Password: ")
        if not password:
            raise ShareError("share password must not be empty")
    client = Client()
    if options["list"]:
        for share in client.request("/api/share/list"):
            expiry = share.get("expire", 0)
            until = (
                datetime.datetime.fromtimestamp(
                    expiry, datetime.timezone.utc
                ).isoformat()
                if expiry
                else "never"
            )
            access = "edit" if share.get("allowModify") else "read"
            status = "available" if share.get("pathExists") else "missing"
            if (
                expiry
                and expiry <= datetime.datetime.now(datetime.timezone.utc).timestamp()
            ):
                status = "expired"
            print(
                f"{share['hash']}\t{access}\t{status}\t{until}\t{share.get('source', '')}:{share['path']}\t{share['shareURL']}"
            )
        return
    if options["revoke"] is not None:
        client.request("/api/share", "DELETE", query={"hash": identifier})
        return
    if not client.local and not options["copy"]:
        raise ShareError("live sharing requires Spark; use --copy")
    sources = client.request("/api/settings", query={"property": "sources"})
    if options["copy"]:
        path = copied_file(client, path, sources)
    source, relative = source_for(path, sources)
    body = {
        "source": source,
        "path": relative,
        "shareType": "normal",
        "allowModify": options["edit"],
        "allowCreate": False,
        "allowDelete": False,
        "allowReplacements": False,
        "showHidden": False,
        "disableSidebar": True,
        "disableLoginOption": True,
        "viewMode": "list",
        "title": path.name,
        "password": password,
        "expires": options["expires"],
        "unit": "seconds",
    }
    result = client.request("/api/share", "POST", body=body)
    if not result.get("shareURL"):
        raise ShareError(
            "share creation was not confirmed; inspect Quantum's Shares page before retrying"
        )
    print(result["shareURL"])


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    try:
        main()
    except OSError as exc:
        name = f"'{exc.filename}': " if exc.filename else ""
        print(f"share: {name}{exc.strerror or exc}", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as exc:
        print(f"share: ssh exited with status {exc.returncode}", file=sys.stderr)
        sys.exit(1)
    except (ShareError, subprocess.TimeoutExpired, ValueError) as exc:
        print(f"share: {exc}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nshare: cancelled", file=sys.stderr)
        sys.exit(130)
