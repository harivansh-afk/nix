# Personal Knowledge Base - Slice 1

Ingestion pipeline and search tool for the Cognee-backed personal knowledge base.

## Files

| File | Purpose |
|------|---------|
| `ingest.py` | Walk corpus, enforce denylist, dedup, ingest into Cognee |
| `kb-search` | CLI query tool; prints top results in plain parseable format |
| `denylist.txt` | One denied path-segment per line |
| `modules/services/kb-ingest.nix` | NixOS module: `kb-search` on PATH + systemd oneshot service |

## Corpus (Slice 1)

- `/home/rathi/Documents/Git/nvim-wiki`
- `/home/rathi/Documents/Git/tmux-wiki`
- `/home/rathi/Documents/Downloads/documents/readings`
- `/home/rathi/Documents/Downloads/documents/school-career`

Supported extensions: `.md`, `.markdown`, `.txt`, `.pdf` (PDF is optional - skipped gracefully if no extractor is installed).

## Denylist

`denylist.txt` contains path segments that are never ingested, even if nested deep in a corpus dir.  A file is skipped if **any component** of its absolute path matches any listed segment.

Additionally, any path component starting with `.` (hidden files/dirs) is always skipped.

The check is fail-safe: on any error during the check, the file is skipped.

Hard-coded fallbacks (always enforced even if the file is missing):

- `.git`
- `node_modules`

Denylist segments include: `security`, `recovery-codes-keys`, `finance-tax`, `travel-identity`, `legal-business`, `.git`, `node_modules`.

## Dry-run (review before ingesting)

Always run dry-run first to see exactly what would be ingested:

```sh
cognee-env python ingest.py --dry-run
```

This lists every file (with a short content hash prefix) that would be added in a real run, plus a summary count.  No Cognee calls are made.

## Real ingestion

```sh
# Run via systemd (manual trigger - never auto-starts):
systemctl start kb-ingest

# Or directly:
cognee-env python ingest.py
```

Ingestion is **incremental and idempotent**: state is tracked in `/var/lib/cognee/ingest-state.json` (path + mtime + SHA-256).  Unchanged files are skipped.  Run again at any time; only new or modified files are processed.

Override state file location:

```sh
cognee-env python ingest.py --state-file /path/to/state.json
```

## Search

```sh
# Via the wrapper on PATH (installed by kb-ingest.nix):
kb-search "what does the neovim wiki say about LSP configuration?"

# Directly:
cognee-env python /path/to/dots/kb/kb-search "your query"
```

Output is plain text, one result per block:

```
RESULT 1
SOURCE: /home/rathi/Documents/Git/nvim-wiki/wiki/...
TEXT:
<excerpt>
---
```

`kb-search` is the tool Hermes calls for knowledge retrieval.

## VERIFY-API seams

The following Cognee API calls have been isolated behind clearly-marked `# VERIFY API` comments in the source.  Confirm against the installed version before the first real ingest:

1. **`cognee.add(data, dataset_name=...)`** - `ingest.py:ingest_file()`.  The `data` argument is a `Path` for text files and a plain `str` (extracted text) for PDFs.  Some versions may require a different type or kwarg name.

2. **`cognee.cognify()`** - `ingest.py:run_cognify()`.  Newer versions may accept `dataset_name=` to limit scope to the Slice-1 dataset; check and add if available.

3. **`cognee.search(query_type=..., query_text=...)`** - `kb-search:search()`.  `SearchType` import path varies across Cognee versions; the script tries two import paths then falls back to a string literal.  Result objects may be dicts or Pydantic models; field-access branches cover common shapes.

## Integration TODOs

- **cognee-env path**: `kb-ingest.nix` calls `cognee-env` by name and expects it on `PATH`.  Once the KB backend module (owned by another agent) finalises the venv layout, update the `ExecStart` / wrapper in `kb-ingest.nix` to use the exact binary path if `cognee-env` is not on the system PATH.  A `TODO: INTEGRATION` comment marks the relevant lines.

- **Dataset isolation**: if Cognee supports per-dataset cognify in the installed version, add `dataset_name=DATASET_NAME` to the `cognify()` call to avoid rebuilding graphs for unrelated datasets.

- **PDF extraction**: install `pypdf` or `pdfminer.six` in the cognee venv if PDF ingestion is wanted.  The pipeline skips PDFs gracefully with a warning if neither is present.

- **State file permissions**: the systemd service runs as `rathi`; ensure `/var/lib/cognee/` is owned by that user or adjust the `StateDirectory` in `kb-ingest.nix`.
