#!/usr/bin/env python3
"""Collect the ix delta and gate the agent at 09:00 America/Los_Angeles."""

from __future__ import annotations

import json
import os
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

PACIFIC = ZoneInfo("America/Los_Angeles")
SQUASH_PR_RE = re.compile(r"\(#(\d+)\)\s*$")
MERGE_PR_RE = re.compile(r"^Merge pull request #(\d+)\b")
REPO_SLUG = os.environ.get("IX_REPO_SLUG", "indexable-inc/ix")
FOCUS_AUTHOR = os.environ.get("IX_FOCUS_AUTHOR", "andrewgazelka")


def run(command: list[str], *, cwd: Path | None = None, timeout: int = 90) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"{' '.join(command)}: timed out after {timeout}s") from exc
    if result.returncode != 0:
        detail = (
            result.stderr.strip()
            or result.stdout.strip()
            or f"exit {result.returncode}"
        )
        raise RuntimeError(f"{' '.join(command)}: {detail}")
    return result.stdout


def now_pacific() -> datetime:
    override = os.environ.get("IX_BRIEF_NOW")
    if override:
        parsed = datetime.fromisoformat(override.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=PACIFIC)
        return parsed.astimezone(PACIFIC)
    return datetime.now(timezone.utc).astimezone(PACIFIC)


def read_state(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, OSError):
        return {}
    return value if isinstance(value, dict) else {}


def emit(value: dict[str, Any]) -> int:
    print(json.dumps(value, separators=(",", ":"), ensure_ascii=False))
    return 0


def git(repo: Path, *args: str, timeout: int = 90) -> str:
    return run(["git", "-C", str(repo), *args], timeout=timeout)


def valid_baseline(repo: Path, sha: str, target: str) -> bool:
    if not sha:
        return False
    result = subprocess.run(
        ["git", "-C", str(repo), "merge-base", "--is-ancestor", sha, target],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def fallback_baseline(repo: Path, target: str, now: datetime) -> str:
    previous_morning = datetime.combine(
        now.date() - timedelta(days=1), time(9), tzinfo=PACIFIC
    )
    cutoff = previous_morning.astimezone(timezone.utc).isoformat()
    baseline = git(repo, "rev-list", "-1", f"--before={cutoff}", target).strip()
    if baseline:
        return baseline
    return git(repo, "rev-list", "--max-parents=0", target).splitlines()[0]


def parse_commits(raw: str) -> list[dict[str, str]]:
    commits: list[dict[str, str]] = []
    for record in raw.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        fields = record.split("\x1f")
        if len(fields) != 7:
            continue
        sha, author_name, author_email, authored_at, subject, body, parents = fields
        commits.append(
            {
                "sha": sha,
                "author_name": author_name,
                "author_email": author_email,
                "authored_at": authored_at,
                "subject": subject,
                "body": body[:1200],
                "parents": parents,
            }
        )
    return commits


def extract_merged_pr(subject: str) -> int | None:
    for pattern in (SQUASH_PR_RE, MERGE_PR_RE):
        match = pattern.search(subject)
        if match:
            return int(match.group(1))
    return None


def gh_json(args: list[str], timeout: int = 12) -> Any:
    gh_bin = os.environ.get("GH_BIN", "gh")
    return json.loads(run([gh_bin, "api", *args], timeout=timeout))


def merged_pr_details(
    numbers: list[int], errors: list[str]
) -> tuple[list[dict[str, Any]], set[int]]:
    def fetch(number: int) -> tuple[int, dict[str, Any] | None, str | None]:
        try:
            pr = gh_json([f"repos/{REPO_SLUG}/pulls/{number}"])
        except (RuntimeError, json.JSONDecodeError) as exc:
            return number, None, f"lookup failed: {exc}"
        base = pr.get("base") if isinstance(pr.get("base"), dict) else {}
        if not pr.get("merged_at") or base.get("ref") != "main":
            return number, None, "API did not confirm a merge into main"
        user = pr.get("user") if isinstance(pr.get("user"), dict) else {}
        return (
            number,
            {
                "number": number,
                "title": pr.get("title", ""),
                "body": (pr.get("body") or "")[:3000],
                "author": user.get("login", ""),
                "url": pr.get("html_url", ""),
                "merged_at": pr.get("merged_at"),
                "additions": pr.get("additions", 0),
                "deletions": pr.get("deletions", 0),
                "changed_files": pr.get("changed_files", 0),
                "base_sha": base.get("sha", ""),
                "head_sha": ((pr.get("head") or {}).get("sha", "")),
                "enriched": True,
            },
            None,
        )

    details: list[dict[str, Any]] = []
    lookup_failed: set[int] = set()
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(fetch, number) for number in numbers[:50]]
        for future in as_completed(futures):
            number, detail, error = future.result()
            if error:
                errors.append(f"PR #{number}: {error}")
                if error.startswith("lookup failed:"):
                    lookup_failed.add(number)
            if detail:
                details.append(detail)
    details.sort(key=lambda item: item["number"])
    return details, lookup_failed


def open_focus_prs(since_date: str, errors: list[str]) -> list[dict[str, Any]]:
    query = (
        f"repo:{REPO_SLUG} is:pr is:open author:{FOCUS_AUTHOR} updated:>={since_date}"
    )
    try:
        result = gh_json(
            ["-X", "GET", "search/issues", "-f", f"q={query}", "-f", "per_page=30"]
        )
    except (RuntimeError, json.JSONDecodeError) as exc:
        errors.append(f"open PR search: {exc}")
        return []
    items = result.get("items", []) if isinstance(result, dict) else []
    output: list[dict[str, Any]] = []
    for item in items[:20]:
        output.append(
            {
                "number": item.get("number"),
                "title": item.get("title", ""),
                "body": (item.get("body") or "")[:2000],
                "url": item.get("html_url", ""),
                "updated_at": item.get("updated_at"),
                "labels": [
                    label.get("name", "")
                    for label in item.get("labels", [])
                    if isinstance(label, dict)
                ],
            }
        )
    return output


def should_wake(state: dict[str, Any], now: datetime, force: bool = False) -> bool:
    if force:
        return True
    return now.hour == 9 and state.get("last_date") != now.date().isoformat()


def main() -> int:
    now = now_pacific()
    loops_dir = Path(os.environ.get("LOOPS_DIR", "/var/lib/loops"))
    brief_dir = loops_dir / "ix-morning-brief"
    state_path = brief_dir / "state.json"
    state = read_state(state_path)
    force = os.environ.get("IX_BRIEF_FORCE") == "1"
    local_date = now.date().isoformat()

    if not should_wake(state, now, force):
        if state.get("last_date") == local_date:
            return emit(
                {
                    "wakeAgent": False,
                    "reason": "already delivered today",
                    "date": local_date,
                }
            )
        return emit(
            {
                "wakeAgent": False,
                "reason": "outside 09:00 Pacific hour",
                "local_time": now.isoformat(),
            }
        )

    repo = Path(os.environ.get("IX_CHECKOUT", "/home/rathi/Documents/Git/indexable/ix"))
    if not repo.exists():
        return emit({"wakeAgent": False, "error": f"ix checkout missing: {repo}"})

    errors: list[str] = []
    try:
        git(repo, "rev-parse", "--is-inside-work-tree", timeout=10)
        git(repo, "fetch", "--quiet", "origin", timeout=60)
        target = git(repo, "rev-parse", "origin/main").strip()
    except RuntimeError as exc:
        return emit({"wakeAgent": True, "error": str(exc), "date": local_date})

    candidate = str(state.get("last_sha", ""))
    baseline = (
        candidate
        if valid_baseline(repo, candidate, target)
        else fallback_baseline(repo, target, now)
    )
    if baseline == target:
        return emit(
            {
                "wakeAgent": False,
                "reason": "no new commits",
                "date": local_date,
                "sha": target,
            }
        )

    log_format = "%H%x1f%aN%x1f%aE%x1f%aI%x1f%s%x1f%b%x1f%P%x1e"
    raw_log = git(
        repo, "log", "--first-parent", f"--format={log_format}", f"{baseline}..{target}"
    )
    commits = parse_commits(raw_log)
    changed_files = [
        line
        for line in git(repo, "diff", "--name-only", baseline, target).splitlines()
        if line
    ][:500]
    commit_prs = {
        number: commit
        for commit in commits
        if (number := extract_merged_pr(commit["subject"])) is not None
    }
    pr_numbers = sorted(commit_prs)
    merged_prs, lookup_failed = merged_pr_details(pr_numbers, errors)
    enriched_numbers = {pr["number"] for pr in merged_prs}
    for number in pr_numbers:
        if number in enriched_numbers or number not in lookup_failed:
            continue
        source = commit_prs[number]
        merged_prs.append(
            {
                "number": number,
                "title": source["subject"],
                "body": source["body"],
                "author": source["author_name"],
                "url": f"https://github.com/{REPO_SLUG}/pull/{number}",
                "enriched": False,
                "subject_verified": True,
            }
        )
    merged_prs.sort(key=lambda item: item["number"])
    since_date = (now.date() - timedelta(days=1)).isoformat()
    open_prs = open_focus_prs(since_date, errors)

    first_time = commits[-1]["authored_at"] if commits else ""
    last_time = commits[0]["authored_at"] if commits else ""
    content_path = brief_dir / "work" / f"content-{local_date}.json"
    output_path = brief_dir / f"ix-morning-brief-{local_date}.html"

    return emit(
        {
            "wakeAgent": True,
            "brief": {
                "date": local_date,
                "repo": REPO_SLUG,
                "focus_author": FOCUS_AUTHOR,
                "from_sha": baseline,
                "to_sha": target,
                "window_start": first_time,
                "window_end": last_time,
                "commit_count": len(commits),
                "merged_pr_count": len(merged_prs),
                "commits": commits,
                "merged_prs": merged_prs,
                "open_focus_prs": open_prs,
                "changed_files": changed_files,
                "collection_errors": errors,
            },
            "paths": {
                "content_json": str(content_path),
                "output_html": str(output_path),
                "state_json": str(state_path),
            },
            "instruction": "Use the ix-morning-brief skill. Write validated concise content JSON, render with /run/current-system/sw/bin/ix-morning-brief-render --advance, then reply with only the HTML MEDIA attachment.",
        }
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"wakeAgent": True, "error": str(exc)}, separators=(",", ":")))
        raise SystemExit(1)
