#!/usr/bin/env python3
"""Render a validated ix morning brief as one self-contained mobile HTML file."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import subprocess
import tempfile
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

SKILL_DIR = Path(__file__).resolve().parent.parent
DEFAULT_TEMPLATE = SKILL_DIR / "templates" / "brief.html"
MAX_WORKSTREAMS = 3
MAX_WATCHLIST = 4
PACIFIC = ZoneInfo("America/Los_Angeles")
SQUASH_PR_RE = re.compile(r"\(#(\d+)\)\s*$")
MERGE_PR_RE = re.compile(r"^Merge pull request #(\d+)\b")


def fail(message: str) -> None:
    raise ValueError(message)


def require_text(value: Any, field: str, limit: int) -> str:
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be non-empty text")
    value = value.strip()
    if len(value) > limit:
        fail(f"{field} exceeds {limit} characters")
    return value


def require_int(value: Any, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        fail(f"{field} must be a non-negative integer")
    return value


def validate(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        fail("brief root must be an object")
    if data.get("schema") != 1:
        fail("schema must be 1")
    require_text(data.get("date"), "date", 10)
    try:
        date.fromisoformat(data["date"])
    except ValueError as exc:
        fail(f"date must be ISO YYYY-MM-DD: {exc}")
    require_text(data.get("repo"), "repo", 120)
    require_text(data.get("headline"), "headline", 70)
    require_text(data.get("summary"), "summary", 260)

    range_data = data.get("range")
    if not isinstance(range_data, dict):
        fail("range must be an object")
    require_text(range_data.get("from_sha"), "range.from_sha", 64)
    require_text(range_data.get("to_sha"), "range.to_sha", 64)
    require_text(range_data.get("window"), "range.window", 80)
    require_int(range_data.get("commit_count"), "range.commit_count")
    require_int(range_data.get("merged_pr_count"), "range.merged_pr_count")

    workstreams = data.get("workstreams")
    if (
        not isinstance(workstreams, list)
        or not 1 <= len(workstreams) <= MAX_WORKSTREAMS
    ):
        fail(f"workstreams must contain 1-{MAX_WORKSTREAMS} items")
    for index, item in enumerate(workstreams):
        if not isinstance(item, dict):
            fail(f"workstreams[{index}] must be an object")
        prefix = f"workstreams[{index}]"
        require_text(item.get("title"), f"{prefix}.title", 48)
        require_text(item.get("thesis"), f"{prefix}.thesis", 140)
        require_text(item.get("now"), f"{prefix}.now", 190)
        evidence = item.get("evidence", [])
        if not isinstance(evidence, list) or len(evidence) > 2:
            fail(f"{prefix}.evidence must contain at most 2 items")
        for evidence_index, fact in enumerate(evidence):
            if not isinstance(fact, dict) or fact.get("kind") != "measurement":
                fail(f"{prefix}.evidence[{evidence_index}] must be a measurement")
            require_text(
                fact.get("label"), f"{prefix}.evidence[{evidence_index}].label", 44
            )
            require_text(
                fact.get("before"), f"{prefix}.evidence[{evidence_index}].before", 30
            )
            require_text(
                fact.get("now"), f"{prefix}.evidence[{evidence_index}].now", 30
            )
        prs = item.get("prs", [])
        if not isinstance(prs, list) or len(prs) > 4:
            fail(f"{prefix}.prs must contain at most 4 items")
        for pr_index, pr in enumerate(prs):
            if not isinstance(pr, dict):
                fail(f"{prefix}.prs[{pr_index}] must be an object")
            require_int(pr.get("number"), f"{prefix}.prs[{pr_index}].number")

    watchlist = data.get("watchlist", [])
    if not isinstance(watchlist, list) or len(watchlist) > MAX_WATCHLIST:
        fail(f"watchlist must contain at most {MAX_WATCHLIST} items")
    for index, item in enumerate(watchlist):
        if not isinstance(item, dict):
            fail(f"watchlist[{index}] must be an object")
        prefix = f"watchlist[{index}]"
        require_text(item.get("title"), f"{prefix}.title", 58)
        require_text(item.get("status"), f"{prefix}.status", 160)
        require_int(item.get("pr"), f"{prefix}.pr")
        if item.get("why") is not None:
            require_text(item["why"], f"{prefix}.why", 130)
    return data


def esc(value: Any) -> str:
    return html.escape(str(value), quote=True)


def pr_refs(prs: list[dict[str, Any]]) -> str:
    return " · ".join(f"#{require_int(pr['number'], 'pr.number')}" for pr in prs)


def render_workstream(index: int, item: dict[str, Any]) -> str:
    metrics = ""
    evidence = item.get("evidence", [])
    if evidence:
        cells = []
        for fact in evidence:
            cells.append(
                '<div><span class="metric-label">'
                + esc(fact["label"])
                + '</span><span class="metric-value">'
                + esc(fact["before"])
                + ' <span class="arrow">→</span> '
                + esc(fact["now"])
                + "</span></div>"
            )
        metrics = '<div class="metrics">' + "".join(cells) + "</div>"
    refs = pr_refs(item.get("prs", []))
    return f"""      <article>
        <div class="number">{index}</div>
        <div>
          <div class="article-head">
            <h2>{esc(item["title"])}</h2>
            <span class="pr">{esc(refs)}</span>
          </div>
          <p class="thesis">{esc(item["thesis"])}</p>
          <div class="delta"><span class="label">Delta</span><span>{esc(item["now"])}</span></div>
          {metrics}
        </div>
      </article>"""


def render_watch(index: int, item: dict[str, Any]) -> str:
    why = ""
    if item.get("why"):
        why = f'<div class="why"><span class="label">Why</span><span>{esc(item["why"])}</span></div>'
    return f"""      <article>
        <div class="number">{index}</div>
        <div>
          <div class="article-head"><h3>{esc(item["title"])}</h3><span class="pr">#{item["pr"]}</span></div>
          <p class="status">{esc(item["status"])}</p>
          {why}
        </div>
      </article>"""


def build_body(data: dict[str, Any]) -> str:
    brief_date = date.fromisoformat(data["date"])
    long_date = brief_date.strftime("%A · %d %b %Y")
    short_date = brief_date.strftime("%d %b %Y")
    range_data = data["range"]
    landed = "\n".join(
        render_workstream(i, item) for i, item in enumerate(data["workstreams"], 1)
    )
    watchlist = data.get("watchlist", [])
    open_section = ""
    if watchlist:
        open_items = "\n".join(
            render_watch(i, item) for i, item in enumerate(watchlist, 1)
        )
        open_section = f"""
    <section class="open-loops" aria-labelledby="open-title">
      <div class="section-head">
        <span class="eyebrow">ix / open loops</span>
        <span class="meta">{esc(short_date)}</span>
      </div>
      <h2 class="section-title" id="open-title">Still moving</h2>
      <p class="section-note">Not landed yet. Each line says what changes and why it matters.</p>
{open_items}
    </section>"""
    repo_name = data["repo"].split("/")[-1]
    return f"""    <header>
      <div class="topline">
        <span class="eyebrow">ix / morning brief</span>
        <span class="meta">{esc(long_date)}</span>
      </div>
      <h1>{esc(data["headline"])}</h1>
      <p class="dek">{esc(data["summary"])}</p>
      <div class="statline" aria-label="Activity summary">
        <span>{range_data["commit_count"]} commits</span>
        <span>{esc(range_data["window"])}</span>
        <span>{range_data["merged_pr_count"]} merged PRs</span>
      </div>
    </header>

    <section class="landed" aria-label="Landed work">
{landed}
    </section>
{open_section}

    <footer>
      <span>{esc(repo_name)} · {esc(range_data["from_sha"][:7])}→{esc(range_data["to_sha"][:7])}</span>
      <span>Private</span>
    </footer>"""


def git_output(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        detail = (
            result.stderr.strip()
            or result.stdout.strip()
            or f"exit {result.returncode}"
        )
        fail(f"git {' '.join(args)}: {detail}")
    return result.stdout.strip()


def extract_merged_pr(subject: str) -> int | None:
    for pattern in (SQUASH_PR_RE, MERGE_PR_RE):
        match = pattern.search(subject)
        if match:
            return int(match.group(1))
    return None


def trusted_range(state_path: Path) -> dict[str, Any]:
    repo = Path(os.environ.get("IX_CHECKOUT", "/home/rathi/Documents/Git/indexable/ix"))
    repo_slug = os.environ.get("IX_REPO_SLUG", "indexable-inc/ix")
    now = datetime.now(timezone.utc).astimezone(PACIFIC)
    target = git_output(repo, "rev-parse", "origin/main")
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        state = {}
    candidate = str(state.get("last_sha", "")) if isinstance(state, dict) else ""
    valid_candidate = False
    if candidate:
        ancestry = subprocess.run(
            ["git", "-C", str(repo), "merge-base", "--is-ancestor", candidate, target],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        valid_candidate = ancestry.returncode == 0
    if valid_candidate:
        baseline = candidate
    else:
        previous_morning = datetime.combine(
            now.date() - timedelta(days=1), time(9), tzinfo=PACIFIC
        )
        cutoff = previous_morning.astimezone(timezone.utc).isoformat()
        baseline = git_output(repo, "rev-list", "-1", f"--before={cutoff}", target)
        if not baseline:
            baseline = git_output(
                repo, "rev-list", "--max-parents=0", target
            ).splitlines()[0]
    commit_count = int(
        git_output(
            repo, "rev-list", "--first-parent", "--count", f"{baseline}..{target}"
        )
    )
    subjects = git_output(
        repo, "log", "--first-parent", "--format=%s", f"{baseline}..{target}"
    ).splitlines()
    merged_prs = {
        number
        for subject in subjects
        if (number := extract_merged_pr(subject)) is not None
    }
    return {
        "date": now.date().isoformat(),
        "repo": repo_slug,
        "from_sha": baseline,
        "to_sha": target,
        "commit_count": commit_count,
        "merged_prs": merged_prs,
    }


def verify_trusted_range(data: dict[str, Any], state_path: Path) -> dict[str, Any]:
    trusted = trusted_range(state_path)
    range_data = data["range"]
    comparisons = {
        "date": (data["date"], trusted["date"]),
        "repo": (data["repo"], trusted["repo"]),
        "range.from_sha": (range_data["from_sha"], trusted["from_sha"]),
        "range.to_sha": (range_data["to_sha"], trusted["to_sha"]),
        "range.commit_count": (range_data["commit_count"], trusted["commit_count"]),
    }
    mismatches = [
        f"{field}: content {actual!r} does not match trusted {expected!r}"
        for field, (actual, expected) in comparisons.items()
        if actual != expected
    ]
    if range_data["merged_pr_count"] > len(trusted["merged_prs"]):
        mismatches.append("range.merged_pr_count exceeds trusted merge-subject count")
    cited = {
        pr["number"]
        for workstream in data["workstreams"]
        for pr in workstream.get("prs", [])
    }
    unknown_citations = cited - trusted["merged_prs"]
    if unknown_citations:
        mismatches.append(
            f"merged PR citations are not in the trusted git delta: {sorted(unknown_citations)}"
        )
    if mismatches:
        fail("trusted range verification failed: " + "; ".join(mismatches))
    return trusted


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    os.chmod(temp_path, 0o600)
    os.replace(temp_path, path)


def advance_state(trusted: dict[str, Any], state_path: Path, output_path: Path) -> None:
    state = {
        "last_date": trusted["date"],
        "last_sha": trusted["to_sha"],
        "last_output": str(output_path.resolve()),
    }
    atomic_write(state_path, json.dumps(state, indent=2, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--template",
        type=Path,
        default=Path(os.environ.get("BRIEF_TEMPLATE", DEFAULT_TEMPLATE)),
    )
    parser.add_argument("--state", type=Path)
    parser.add_argument("--advance", action="store_true")
    args = parser.parse_args()

    data = validate(json.loads(args.input.read_text(encoding="utf-8")))
    state_path = args.state
    managed_state = os.environ.get("BRIEF_STATE")
    if managed_state:
        managed_path = Path(managed_state)
        if state_path is not None and state_path.resolve() != managed_path.resolve():
            fail("--state does not match the managed state path")
        state_path = managed_path
    if state_path is None:
        loops_dir = Path(os.environ.get("LOOPS_DIR", "/var/lib/loops"))
        state_path = loops_dir / "ix-morning-brief" / "state.json"
    trusted = verify_trusted_range(data, state_path) if args.advance else None

    template = args.template.read_text(encoding="utf-8")
    if (
        template.count("{{BODY}}") != 1
        or template.count("{{TITLE}}") != 1
        or template.count("{{") != 2
        or template.count("}}") != 2
    ):
        fail("template must contain exactly one {{TITLE}} and one {{BODY}} marker")
    title = f"ix morning brief · {data['date']}"
    output = template.replace("{{TITLE}}", esc(title)).replace(
        "{{BODY}}", build_body(data)
    )
    atomic_write(args.output, output)

    if args.advance:
        assert trusted is not None
        advance_state(trusted, state_path, args.output)
    print(str(args.output.resolve()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
