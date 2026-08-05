---
name: feed-triage
description: "Use when running as a scheduled feed-triage cron job (x-life-scan, hn-life-scan, dep-release-watch). Judge which gathered items have a real consequence for what Hari is working on right now, file a KB note for the survivors, and either send one terse ping or stay silent."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [feed, triage, cron, proactive, surfacing, kb, attention]
    related_skills: [read-it-later]
---

# Feed triage (proactive surfacings)

## Overview

You are the judgment step of one of Hari's feed loops. A pre-run script has
already gathered raw items and injected them under `## Script Output`. Your job
is to decide which of them - if any - are worth interrupting him for, write the
durable record into the KB, and then either send one terse ping or go silent.

The bar is high on purpose. Hari's attention is the scarce resource, not the
supply of items. A run that surfaces nothing is a *successful* run, and it is
the common case. Do not manufacture relevance to justify sending something.

You are running as cron, so your final response IS the message. Do not call
`send_message`. To stay silent, reply with exactly `[SILENT]` and nothing else.

## The loops

| Job | Items are | Source ref to cite |
|-----|-----------|--------------------|
| `x-life-scan` | posts from Hari's logged-in X home feed | the post URL |
| `hn-life-scan` | Hacker News front-page stories | the story URL |
| `dep-release-watch` | new releases of watched dependency repos | the release URL |

The job name is in your prompt. Every item you surface must carry its source
ref. If an item has no usable URL, do not surface it.

## Workflow

### 1. Ground yourself in what he is actually working on

Do not guess, and do not rely on a static list. Establish current context first:

- `kb_search` for recent activity on his repos and projects (the `forgejo`
  source carries his commits and PRs).
- `terminal`: `ls -t ~/Documents/Git` and `git -C <repo> log -1 --format=%s`
  for repos with recent local commits.
- `session_search` for what he has been talking to you about lately.

Two or three lookups is enough. This grounding is the whole reason an agent
does this job instead of a script - use it.

### 2. Judge

For each item ask one question: **does this change something for a project Hari
is working on right now?**

Surface it only if you can name the specific project and state the concrete
consequence in one sentence. A real hit looks like "the library you pin in X
shipped the thing that unblocks Y". A fake hit looks like "this is about NixOS
and Hari uses NixOS".

Reject, without exception:

- Generic tech news, hype, drama, engagement bait, hot takes.
- Incremental releases: patch bumps, docs/CI changes, routine point releases.
  `dep-release-watch` only earns a ping for breaking changes, major new
  capabilities, significant performance wins, or security fixes that affect him.
- Anything where the tie to a project needs more than one sentence to explain.
  If you have to argue for it, it is not a hit.

### 3. Check you are not repeating yourself

Before surfacing, `kb_search` the item's topic and skim
`/var/lib/kb/staging/loops/` for a prior note covering the same thing. If a
previous run already surfaced it, drop it. Repeating a surfacing is worse than
missing one.

### 4. File the KB note (only if something survived)

Write the full record with `write_file` to:

```
/var/lib/kb/staging/loops/<job-name>/<YYYY-MM-DDTHH:MM:SSZ>.md
```

Get the timestamp from `terminal` (`date -u +%FT%TZ`); do not guess it. The
directory MUST be the job name, because the indexer derives the KB `source`
from the parent directory. The hourly `kb-ingest` picks the note up, which is
how you answer "where did you get this?" later.

#### Note template

```markdown
# <job-name> <YYYY-MM-DD>

- Source: loops
- Loop: <job-name>
- Run: <YYYY-MM-DDTHH:MM:SSZ>
- Gathered: <count of items in the script output>
- Surfaced: <count you kept>

## Surfaced

### <headline>
- URL: <source ref>
- Project: <the active project it ties to>
- Why: <the concrete consequence, one or two sentences>

## Considered and dropped
- <item> - <one-line reason>
```

Keep the dropped list short (the near-misses, not all 40). It is there so the
gate stays inspectable.

### 5. Ping, or stay silent

If nothing survived, reply with exactly:

```
[SILENT]
```

Nothing else. No preamble, no "nothing to report today". The `[SILENT]` marker
suppresses delivery; the run is still recorded.

If something survived, send at most **three** items, one sentence each, each
line carrying the loop label and the source ref:

```
[hn-life-scan] llama.cpp landed native GB10 kernels - your inference server is
the exact target, worth a rebuild. https://news.ycombinator.com/item?id=...
```

No greeting, no sign-off, no "I found some interesting things for you". Lead
with the substance. If one item is worth sending, send one item.

## Common pitfalls

1. **Stretching for a project tie.** The most common failure. When in doubt,
   `[SILENT]`.
2. **Sending without a source ref.** Every line needs its URL. Hari will ask
   where it came from and you must be able to point at it.
3. **Skipping the KB note.** If you ping without filing the note, the surfacing
   becomes unciteable an hour later. Note first, then ping.
4. **Combining `[SILENT]` with content.** It is the whole response or not at
   all.
5. **Using `send_message`.** Your final response is delivered automatically.
   Calling the tool double-sends.
6. **Writing the note when nothing survived.** No survivors, no note. Just
   `[SILENT]`.
7. **Padding to three items.** Three is a cap, not a target.

## Verification checklist

- [ ] Grounded against current repo/session activity, not a guessed project list.
- [ ] Every surfaced item names a specific project and a concrete consequence.
- [ ] Checked prior loop notes so nothing is surfaced twice.
- [ ] KB note written under `/var/lib/kb/staging/loops/<job-name>/` with a real
      `date -u` timestamp (only if something survived).
- [ ] Response is either `[SILENT]` alone, or at most 3 sentences each with a
      loop label and a URL.
