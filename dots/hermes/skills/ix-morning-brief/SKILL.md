---
name: ix-morning-brief
description: "Use only for the managed ix-morning-brief cron run. Turn the gathered ix delta into a concise, grounded mobile HTML brief and deliver one HTML attachment."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [ix, brief, cron, proactive, html]
---

# ix morning brief

The gather payload under `## Script Output` is the source of truth. It contains the exact `origin/main` delta since the last successful brief, enriched merged PR metadata, Andrew Gazelka's recently updated open PRs, and output paths.

The reader is Hari on his phone. This is a one-minute morning scan, not a changelog. The approved HTML visual template is frozen. Your job is judgment and compression.

## Workflow

1. Read `brief`, `paths`, and any `collection_errors` from the gather payload.
2. Group landed work by outcome, not directory or commit chronology.
3. Rank ruthlessly. Keep at most three landed workstreams and four open loops. Fold lesser landed work into the summary or omit it.
4. Focus on Andrew Gazelka's work. Include another contributor only when their change is necessary to explain the resulting state of `main`.
5. Write the content JSON to the exact `paths.content_json` path with `write_file`.
6. Run:

```sh
/run/current-system/sw/bin/ix-morning-brief-render \
  --input <paths.content_json> \
  --output <paths.output_html> \
  --state <paths.state_json> \
  --advance
```

7. If rendering succeeds, reply with exactly:

```text
MEDIA: <paths.output_html>
```

No caption or second bubble. Cron delivers the final response.

## Content schema

```json
{
  "schema": 1,
  "date": "2026-08-05",
  "repo": "indexable-inc/ix",
  "range": {
    "from_sha": "verbatim payload brief.from_sha",
    "to_sha": "verbatim payload brief.to_sha",
    "commit_count": 51,
    "merged_pr_count": 38,
    "window": "Tue 22:04 → Wed 10:03 PT"
  },
  "headline": "The most consequential change, 70 chars max.",
  "summary": "One compact framing paragraph, 260 chars max.",
  "workstreams": [
    {
      "title": "Cache and CI trust",
      "thesis": "What materially changed and why it matters, 140 chars max.",
      "now": "The concrete resulting behavior, 190 chars max.",
      "evidence": [
        {
          "kind": "measurement",
          "label": "restore index",
          "before": "2.00 GiB",
          "now": "648 B"
        }
      ],
      "prs": [{"number": 9949, "title": "Optional short source title"}]
    }
  ],
  "watchlist": [
    {
      "title": "Warm-donor-aware placement",
      "status": "The exact current open state, 160 chars max.",
      "why": "Optional consequence, 130 chars max.",
      "pr": 9945
    }
  ]
}
```

Hard caps enforced by the renderer:

- 1-3 workstreams.
- At most two measurements and four PR references per workstream.
- At most four watchlist items.
- Optional `why` is omitted when there is no real consequence.
- Only `measurement` evidence is accepted. Skip soft claims rather than dressing them up as evidence.

## Grounding rules

- Every number and before/after statement must appear in a commit, PR body, or gather field.
- Copy all range SHAs and counts verbatim from the payload.
- Cite only PR numbers present in `merged_prs` or `open_focus_prs`.
- A thesis describes the resulting state, not the activity: "a wrong signing key now fails" beats "improved cache validation".
- No raw commit dump, exhaustive file list, vanity addition/deletion counts, hype, exclamation marks, or em dashes.
- If enrichment failed, use the git evidence that remains. Mention degraded collection only when it materially limits the conclusions.
- Do not edit the template or state file. `--advance` updates state only after the HTML is written successfully.

## Failure behavior

If validation fails, trim or correct the JSON and retry twice. If rendering still fails, return one short error line. Never emit a `MEDIA:` path for a file that was not created, and never advance state manually.
