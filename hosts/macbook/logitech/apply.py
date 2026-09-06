"""Apply the owned mouse controls without replacing unrelated Options+ state."""

import copy
import datetime
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time


def configure(current, defaults, policy):
    result = copy.deepcopy(current)
    default_key = defaults["profile_keys"][0]
    global_profile = result[default_key]
    template = next(
        a["card"] for a in defaults[default_key]["assignments"]
        if a["slotId"] == policy["devices"][0] + "_c195"
    )

    def controls(profile, browser):
        assignments = {a["slotId"]: a for a in profile["assignments"]}
        for device in policy["devices"]:
            gesture = copy.deepcopy(template)
            gesture["selectedNestedCard"] = "custom_gesture"
            nested = gesture["nestedCards"]["custom_gesture"]["nestedCards"]
            for direction, action in (
                ("click", "copy"),
                ("left", "back" if browser else "nothing"),
                ("right", "forward" if browser else "nothing"),
            ):
                nested[direction] = copy.deepcopy(policy["cards"][action])
            for suffix, card in (("c195", gesture), ("c86", policy["cards"]["paste"])):
                slot = device + "_" + suffix
                assignments[slot] = {
                    "slotId": slot, "cardId": card["id"],
                    "card": copy.deepcopy(card), "tags": ["UI_PAGE_BUTTONS"],
                }
        profile["assignments"] = list(assignments.values())

    controls(global_profile, False)
    applications = result["applications"]["applications"]
    for browser in policy["browsers"]:
        app = next((a for a in applications if
                    a.get("bundleId") == browser["bundleId"] or
                    a.get("applicationId") == browser["applicationId"] or
                    a.get("applicationPath") == browser["applicationPath"]), None)
        if app is None:
            app = {**browser, "databaseId": browser["applicationId"],
                   "applicationPathsList": [browser["applicationPath"]]}
            applications.append(app)
        app_id = app["applicationId"]
        key = "profile-" + app_id
        if key not in result:
            result[key] = copy.deepcopy(global_profile)
            result[key].update(id=app_id, applicationId=app_id, name=browser["name"])
        result[key]["activeForApplication"] = True
        controls(result[key], True)
        if key not in result["profile_keys"]:
            result["profile_keys"].append(key)
    return result


def read(db):
    rows = db.execute("SELECT _id, file FROM data").fetchall()
    if len(rows) != 1:
        raise RuntimeError("Unexpected Options+ database shape; refusing to modify it")
    return rows[0][0], json.loads(rows[0][1])


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=20)


def apply(source, destination):
    defaults = json.loads((source / "settings.json").read_text())
    policy = json.loads((source / "mappings.json").read_text())
    target = destination / "settings.db"
    with sqlite3.connect(f"file:{target}?mode=ro", uri=True) as db:
        _, current = read(db)
    if configure(current, defaults, policy) == current:
        print("Logitech mappings already match")
        return

    domain = f"gui/{os.getuid()}"
    plist = "/Library/LaunchAgents/com.logi.optionsplus.plist"
    loaded = run("/bin/launchctl", "print", domain + "/com.logi.cp-dev-mgr", check=False).returncode == 0
    gui = run("/usr/bin/pgrep", "-x", "logioptionsplus", check=False).returncode == 0
    if gui:
        run("/usr/bin/osascript", "-e", 'tell application id "com.logi.optionsplus" to quit')
    stopped = False
    try:
        if loaded:
            run("/bin/launchctl", "bootout", domain, plist)
            stopped = True
        for _ in range(50):
            if run("/usr/bin/pgrep", "-x", "logioptionsplus_agent", check=False).returncode != 0:
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("Logitech backend is still running; refusing to race its database writes")

        with sqlite3.connect(target) as db:
            ident, current = read(db)
            updated = configure(current, defaults, policy)
            backup_dir = destination.parent / "LogiOptionsPlus-backups"
            backup_dir.mkdir(mode=0o700, exist_ok=True)
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup_path = backup_dir / f"settings-{stamp}.db"
            with sqlite3.connect(backup_path) as backup:
                db.backup(backup)
            os.chmod(backup_path, 0o600)
            db.execute("UPDATE data SET file=? WHERE _id=?",
                       (json.dumps(updated, separators=(",", ":")).encode(), ident))
            if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise RuntimeError("Options+ database integrity check failed")
        print(f"Applied Logitech mappings; previous settings saved to {backup_path}")
    finally:
        if stopped:
            run("/bin/launchctl", "bootstrap", domain, plist)
        if gui:
            run("/usr/bin/open", "/Applications/logioptionsplus.app")


if __name__ == "__main__":
    source, destination = map(Path, sys.argv[1:])
    with (destination / ".nix-mappings.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        apply(source, destination)
