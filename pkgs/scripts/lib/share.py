"""Create FileBrowser Quantum links to existing Spark files."""

import argparse
import datetime
import getpass
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


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
            "http://127.0.0.1:39473"
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
            "ssh",
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
            raise ShareError(
                f"Quantum rejected {method} {path} (HTTP {exc.code})"
            ) from None
        except urllib.error.URLError as exc:
            raise ShareError(f"cannot reach Quantum: {exc.reason}") from None
        if raw or not content:
            return content
        return json.loads(content)


def expiration(value):
    match = re.fullmatch(r"([1-9][0-9]{0,5})(m|h|d|w)", value)
    if not match:
        raise argparse.ArgumentTypeError(
            "expected a duration such as 30m, 2h, 7d or 2w"
        )
    seconds = int(match[1]) * {"m": 60, "h": 3600, "d": 86400, "w": 604800}[match[2]]
    if seconds > 9_223_372_036:
        raise argparse.ArgumentTypeError("expiry exceeds Quantum's duration limit")
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
        roots = ", ".join(source["path"] for source in sources)
        raise ShareError(
            f"path is outside Quantum's sources ({roots}); use --copy for a snapshot"
        )
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
    print(f"Uploading a snapshot of {path.name} to Spark…", file=sys.stderr)

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
    parser = argparse.ArgumentParser(
        prog="share",
        description="Share an original Spark file through FileBrowser Quantum.",
        epilog="share list · share revoke ID · share ./notes.md --edit · share ./file --copy",
    )
    parser.add_argument("target", metavar="PATH|list|revoke")
    parser.add_argument("identifier", nargs="?", metavar="ID")
    parser.add_argument(
        "--edit", action="store_true", help="allow saving changes to the shared file"
    )
    parser.add_argument(
        "--expires", type=expiration, help="expire after 30m, 2h, 7d, etc."
    )
    parser.add_argument(
        "--password", action="store_true", help="prompt for a password for this link"
    )
    parser.add_argument(
        "--copy",
        action="store_true",
        help="upload a snapshot instead of sharing the original",
    )
    parser.add_argument(
        "--version", action="version", version="share (FileBrowser Quantum)"
    )
    args = parser.parse_args()
    managing = args.target in ("list", "revoke")
    if managing and (args.edit or args.expires or args.password or args.copy):
        parser.error("sharing options apply to a file or folder, not list/revoke")
    if (args.target == "revoke") != (args.identifier is not None):
        parser.error("use 'share revoke ID', 'share list', or 'share PATH'")
    path = None
    if not managing:
        path = Path(args.target).expanduser()
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
    if args.password:
        password = getpass.getpass("Password for this link: ")
        if not password:
            raise ShareError("share password must not be empty")
    client = Client()
    if args.target == "list":
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
    if args.target == "revoke":
        identifier = share_id(args.identifier)
        client.request("/api/share", "DELETE", query={"hash": identifier})
        print(f"Revoked {identifier}", file=sys.stderr)
        return
    if not client.local and not args.copy:
        raise ShareError(
            "this file is local to this computer; use --copy to upload a snapshot, or run share on Spark for a live link"
        )
    sources = client.request("/api/settings", query={"property": "sources"})
    if args.copy:
        path = copied_file(client, path, sources)
    source, relative = source_for(path, sources)
    body = {
        "source": source,
        "path": relative,
        "shareType": "normal",
        "allowModify": args.edit,
        "allowCreate": False,
        "allowDelete": False,
        "allowReplacements": False,
        "showHidden": False,
        "disableSidebar": True,
        "disableLoginOption": True,
        "viewMode": "list",
        "title": path.name,
        "password": password,
        "expires": args.expires or "",
        "unit": "seconds",
    }
    result = client.request("/api/share", "POST", body=body)
    if not result.get("shareURL"):
        raise ShareError(
            "share creation was not confirmed; inspect Quantum's Shares page before retrying"
        )
    print(result["shareURL"])


if __name__ == "__main__":
    try:
        main()
    except (ShareError, OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"share: {exc}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nshare: cancelled", file=sys.stderr)
        sys.exit(130)
