#!/usr/bin/env python3
"""reconcile.py - make hermes cron jobs match the nix-generated manifest.

Hermes keeps scheduled jobs in ~/.hermes/cron/jobs.json, mutable state the agent
itself writes to (via /cron in chat). We do not own that file outright: we own a
NAMED SUBSET of it. This script reads the manifest and converges exactly those
jobs, leaving anything Hari created by hand untouched. Names it installed last
run are tracked in ~/.hermes/cron/.nix-managed.json; a name that drops out of
the manifest is removed, a name that was never in it is never touched, and a
pre-existing job with a manifest name is adopted.

It runs under hermes' own python environment and imports hermes' cron.jobs
module directly (create_job / update_job / remove_job), so schedule parsing,
next_run_at computation, normalization, and file locking are all first-party -
nothing here reimplements hermes semantics, and the running gateway (which
re-reads jobs.json every scheduler tick) picks changes up on its own.

Manifest shape ($HERMES_CRON_MANIFEST, written by modules/services/hermes-loops.nix):

  {
    "jobs": [
      {
        "name": "hn-life-scan",
        "schedule": "0 */6 * * *",
        "prompt": "...",
        "skills": ["feed-triage"],
        "script": "hn-life-scan.py",
        "deliver": "photon"
      }
    ],
    "scripts": {"hn-life-scan.py": "/nix/store/.../hn-life-scan.py"}
  }

`scripts` are COPIED into ~/.hermes/scripts/ (hermes resolves script paths and
rejects anything outside that directory, so a store symlink resolves out and is
blocked).

`deliver: "photon"` is resolved at run time against ~/.hermes/channel_directory.json
rather than hardcoded, because the DM id is a phone number and this repo is
mirrored publicly. Only the resolved `photon:<chat_id>` form is accepted by
hermes (bare `photon` is not in its delivery-platform allowlist). If no photon
DM is known yet (first boot), the job is installed with `local` delivery and a
warning is logged; the next reconcile after the first DM fixes it up.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

import cron.jobs as cron_jobs

HERMES_HOME = Path(
    os.environ.get("HERMES_HOME") or (Path.home() / ".hermes")
).expanduser()
CRON_DIR = HERMES_HOME / "cron"
MANAGED_FILE = CRON_DIR / ".nix-managed.json"
SCRIPTS_DIR = HERMES_HOME / "scripts"
CHANNEL_DIRECTORY = HERMES_HOME / "channel_directory.json"

# The desired-state fields we own on a managed job. Everything else on the
# record (state, counters, timestamps, snapshots) belongs to hermes.
MANAGED_FIELDS = ("prompt", "skills", "script", "deliver")


def log(message: str) -> None:
    print(f"hermes-cron-reconcile: {message}", flush=True)


def load_json(path: Path, fallback):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        return fallback
    except (OSError, json.JSONDecodeError) as exc:
        log(f"could not read {path}: {exc}")
        return fallback


def resolve_photon_dm() -> str | None:
    override = os.environ.get("HERMES_LOOPS_DELIVER", "").strip()
    if override:
        return override
    directory = load_json(CHANNEL_DIRECTORY, {})
    channels = (directory.get("platforms") or {}).get("photon") or []
    dms = [c for c in channels if c.get("type") == "dm" and c.get("id")]
    if not dms:
        return None
    if len(dms) > 1:
        log(f"{len(dms)} photon DMs known; using the first")
    return f"photon:{dms[0]['id']}"


def install_scripts(scripts: dict[str, str]) -> None:
    SCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    for name, source in scripts.items():
        target = SCRIPTS_DIR / name
        shutil.copyfile(source, target)
        target.chmod(0o755)
    if scripts:
        log(f"installed {len(scripts)} script(s) into {SCRIPTS_DIR}")


def desired_updates(current: dict, desired: dict) -> dict:
    """The update_job payload needed to converge `current`, or {} if in sync."""
    updates = {}
    for field in MANAGED_FIELDS:
        want = desired.get(field) or ([] if field == "skills" else None)
        have = current.get(field) or ([] if field == "skills" else None)
        if want != have:
            updates[field] = desired.get(field)
    if current.get("schedule") != cron_jobs.parse_schedule(desired["schedule"]):
        updates["schedule"] = desired["schedule"]
    if not current.get("enabled", True):
        updates["enabled"] = True
    return updates


def main() -> int:
    manifest_path = os.environ.get("HERMES_CRON_MANIFEST", "")
    manifest = load_json(Path(manifest_path), None) if manifest_path else None
    if manifest is None:
        log(f"manifest {manifest_path or '(unset)'} is missing or unparseable")
        return 2

    install_scripts(manifest.get("scripts") or {})

    deliver_photon = None
    desired_by_name: dict[str, dict] = {}
    for entry in manifest.get("jobs") or []:
        job = dict(entry)
        if job.get("deliver") == "photon":
            if deliver_photon is None:
                deliver_photon = resolve_photon_dm() or "local"
                if deliver_photon == "local":
                    log("no photon DM known yet; delivering locally until one appears")
            job["deliver"] = deliver_photon
        desired_by_name[job["name"]] = job

    existing_by_name: dict[str, dict] = {}
    for job in cron_jobs.list_jobs(include_disabled=True):
        existing_by_name.setdefault(job.get("name"), job)

    previously_managed = set(load_json(MANAGED_FILE, {}).get("names") or [])
    failures = 0

    for name in sorted(previously_managed - set(desired_by_name)):
        job = existing_by_name.get(name)
        if not job:
            continue
        log(f"removing {name} (dropped from the manifest)")
        failures += not cron_jobs.remove_job(job["id"])

    for name, desired in sorted(desired_by_name.items()):
        current = existing_by_name.get(name)
        try:
            if current is None:
                log(f"creating {name}")
                cron_jobs.create_job(
                    prompt=desired.get("prompt"),
                    schedule=desired["schedule"],
                    name=name,
                    deliver=desired.get("deliver"),
                    skills=desired.get("skills"),
                    script=desired.get("script"),
                )
                continue
            updates = desired_updates(current, desired)
            if name not in previously_managed:
                log(f"adopting existing job {name} ({current['id']})")
            elif not updates:
                continue
            else:
                log(f"updating {name} ({current['id']}): {', '.join(sorted(updates))}")
            if updates and cron_jobs.update_job(current["id"], updates) is None:
                raise RuntimeError("job vanished during update")
        except Exception as exc:  # noqa: BLE001 - report and keep converging
            log(f"{name}: {exc}")
            failures += 1

    CRON_DIR.mkdir(parents=True, exist_ok=True)
    tmp = MANAGED_FILE.with_suffix(".tmp")
    tmp.write_text(
        json.dumps({"names": sorted(desired_by_name)}, indent=2), encoding="utf-8"
    )
    os.replace(tmp, MANAGED_FILE)

    if failures:
        log(f"{failures} operation(s) failed")
        return 1
    log(f"in sync: {', '.join(sorted(desired_by_name)) or '(no jobs)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
