---
name: read-it-later
description: "Use when Hari shares a URL (article, YouTube, tweet, paper, repo) to save or read later. Fetch it, write a high-signal summary note into the KB staging dir so it becomes searchable, then confirm with a one-line gist."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [read-it-later, save, capture, second-brain, kb, summarize, bookmarks]
    related_skills: [obsidian, arxiv]
---

# Read It Later (save to second brain)

## Overview

Hari's "save this" capture loop. When he drops a link, you turn it into a
permanent, searchable note in his knowledge base instead of letting it scroll
away. You fetch the page, distill it to high-signal points, tag it, and write a
normalized markdown note into the KB staging dir `/var/lib/kb/staging/saved/`.
The hourly `kb-ingest` reindex picks it up automatically, so later he can ask
"what was that piece on X" and `kb-search` finds it. This compounds: every link
he shares becomes recall.

This is an internal/read+organize action (fetch, summarize, file locally), so
do it on your own - no permission needed. The note never leaves the machine.

## When to Use

- Hari sends a bare URL, or a URL with "save this", "read later", "file this",
  "for later", "remember this", or similar.
- He shares an article, blog post, YouTube video, tweet/X thread, paper
  (arXiv/PDF), or GitHub repo and the intent is to keep it, not discuss it now.

Don't use for:

- A link he's clearly asking you to act on *right now* ("summarize this and tell
  me", "is this legit?") - answer first; you can still offer to save it after.
- Denylisted / sensitive content (see TOOLS.md DENYLIST). If a link points at
  finance/tax, legal, identity, or credentials material, do not file it - stop
  and ask.
- Login-walled pages you can't fetch. Say so rather than saving an empty note.

## Workflow

### 1. Detect and acknowledge
Notice the URL. A short ack is fine ("saving that...") but skip if you'll
confirm in one shot.

### 2. Fetch the content
Use `web_extract` (Firecrawl -> clean markdown) as the default:

```
web_extract(urls=["https://example.com/the-article"])
```

Source-specific notes:

| Source | How to fetch |
|--------|--------------|
| Article / blog | `web_extract(urls=["<url>"])` |
| arXiv | `web_extract(urls=["https://arxiv.org/abs/<id>"])` (see `arxiv` skill) |
| PDF | `web_extract(urls=["<pdf-url>"])` |
| YouTube | `web_extract` the watch URL for title/description; if a transcript is needed and extract is thin, try `terminal` with `yt-dlp --skip-download --write-auto-sub --sub-format vtt -o - "<url>"` if available, else summarize from title + description + any visible transcript. |
| Tweet / X | `web_extract` the status URL; X often blocks - if it returns nothing, fall back to `web_search` for the quoted text, or note that the content was unavailable. |
| GitHub repo | `web_extract` the repo URL (gets the README) for what it is + why it matters. |

If a fetch returns essentially nothing, do NOT write a hollow note. Try one
fallback (`web_search` the title/quote). If still empty, tell Hari it was
unreachable and ask whether to save just the link as a stub.

### 3. Distill (high signal, no fluff)
From the fetched content produce:

- **Title** - the real title of the piece (not the slug).
- **One-line gist** - what it is in a single sentence.
- **Key points** - 3 to 7 bullets, the actual claims/takeaways. No padding,
  no "the author discusses". State the substance.
- **Why it matters / why saved** - one line on the angle worth remembering.
- **Entities** - notable people, companies, tools, papers mentioned.
- **Tags** - 3 to 6 lowercase hyphenated topic tags for retrieval
  (e.g. `inference`, `local-llm`, `rag`, `nixos`).

Hari hates fluff. If the piece is thin, a 3-bullet note is correct - do not
inflate it.

### 4. Write the note
Generate a filesystem-safe slug from the title and write to
`/var/lib/kb/staging/saved/<YYYY-MM-DD>-<slug>.md`. Use the `file` tool
(`write_file`) with a concrete absolute path - do not rely on shell expansion.

Slug rule: lowercase the title, replace any run of non-alphanumeric chars with a
single `-`, trim leading/trailing `-`, cap at ~60 chars. Example title
"Why Local Inference Wins" on 2026-06-26 ->
`/var/lib/kb/staging/saved/2026-06-26-why-local-inference-wins.md`.

Use the exact note template below. Resolve today's date with `terminal`
(`date +%F`) if you are unsure of it - do not guess the date.

#### Note template

```markdown
# <Title>

- Source: saved
- URL: <original url>
- Type: <article | youtube | tweet | paper | repo | pdf>
- Saved: <YYYY-MM-DD>
- Tags: <tag1>, <tag2>, <tag3>

## Gist
<one sentence>

## Key points
- <point 1>
- <point 2>
- <point 3>

## Why saved
<one line on the angle worth remembering>

## Entities
<people / companies / tools / papers, comma-separated; omit line if none>
```

Keep the `- Source: saved` line - it mirrors the staging source name and keeps
notes self-describing. (The indexer also derives `source` from the parent dir,
so the directory MUST be `saved/`.)

### 5. Confirm to Hari
One line, lead with the gist. Example:

> saved -> "Why Local Inference Wins": the latency + privacy case for running
> models on your own box. tagged local-llm, inference. it's in the KB now.

Do not dump the whole note back at him unless he asks.

## Common Pitfalls

1. **Writing to the wrong dir.** It must be `/var/lib/kb/staging/saved/` - the
   indexer globs `/var/lib/kb/staging/*/*.md` and uses the parent dir as the
   `source`. A note elsewhere won't be searchable as `saved`.
2. **Saving an empty note.** If the fetch failed, don't file a hollow stub
   silently. Try one fallback, then ask.
3. **Fluff.** Bullets that restate the title or say "the article explains" add
   nothing. Cut them. Substance only.
4. **Guessing the date.** Resolve it with `date +%F`; a wrong date pollutes the
   filename and the `Saved:` field.
5. **Overwriting on re-save.** If the same URL is sent again, a same-day slug
   collides - that's fine (idempotent refresh). If it's a different day, a new
   dated file is created; that's also fine.
6. **Filing sensitive links.** Finance/tax, legal, identity, or credential
   material is denylisted - do not save it. Stop and ask.

## Verification Checklist

- [ ] Fetched real content (not an empty/blocked page).
- [ ] Note written under `/var/lib/kb/staging/saved/` with a dated, slugged name.
- [ ] Frontmatter lines present: Source, URL, Type, Saved, Tags.
- [ ] Key points are substantive (3-7 bullets, no fluff).
- [ ] Confirmed to Hari with a one-line gist, not a wall of text.

## One-Shot Recipe

Hari sends `https://example.com/local-inference-wins`:

1. `web_extract(urls=["https://example.com/local-inference-wins"])`
2. Distill: title, gist, 4 key points, tags `[local-llm, inference, privacy]`.
3. `date +%F` -> `2026-06-26`.
4. `write_file("/var/lib/kb/staging/saved/2026-06-26-local-inference-wins.md", <template>)`.
5. Reply: `saved -> "..." : <gist>. in the KB now.`
