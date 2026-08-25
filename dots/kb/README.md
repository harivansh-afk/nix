# Personal knowledge base

Local ingestion, hybrid retrieval, and Cognee graph enrichment for the personal
knowledge base.

## Files

| File | Purpose |
|------|---------|
| `kb_vec.py` | Hourly chunking, embedding, and hybrid vector/full-text retrieval |
| `kb_graph.py` | Read-only entity resolution and source lookup over Cognee's graph |
| `ingest.py` | Legacy direct Cognee corpus ingestion utility |
| `denylist.txt` | One denied path-segment per line |
| `hosts/spark/services/kb-ingest.nix` | NixOS module providing `kb-search` and the vector indexer |

## Active architecture

Source connectors normalize Gmail, Calendar, Forgejo, downloads, saved links,
research, and loop results into `/var/lib/kb/staging/<source>/`.

- Hourly, `kb_vec.py ingest` rebuilds the fast Postgres index. Documents are
  chunked and embedded locally with Qwen3-Embedding-0.6B. Search fuses HNSW
  pgvector similarity with Postgres full-text ranking.
- Nightly, Cognee adds unchanged documents idempotently and runs `cognify` with
  the local Qwen inference server. This produces the entity graph used only for
  relationship and provenance fallback.

The finance dataset is excluded by default from `kb-search`, `kb-graph resolve`,
and `kb-graph source`. Finance remains available only to separate local
workflows.

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

## Vector ingestion

The active hourly indexer can also be run on demand:

```sh
systemctl start kb-ingest
```

It performs a deterministic full reload of the chunk table, then recreates the
HNSW and full-text indexes. It does not invoke an LLM or Cognee.

## Legacy direct Cognee utility

`ingest.py` predates the source-organized nightly graph builder. Keep it for
manual corpus experiments; it is not used by the active timers.

```sh
cognee-env python ingest.py --dry-run
cognee-env python ingest.py
```

This utility tracks `/var/lib/cognee/ingest-state.json`; unchanged files are
skipped.

## Search

```sh
# Hybrid chunk search (kb_vec.py wrapper on PATH from kb-ingest.nix;
# no LLM, no graph, any user, ~0.5s):
kb-search "what does the neovim wiki say about LSP configuration?"

# Cognee knowledge-graph query via the first-party CLI. The venv is
# root-owned (0750), hence sudo; cognee-env supplies the local-provider env:
sudo cognee-env /var/lib/cognee/venv/bin/cognee-cli search "who invited me to the party?"
sudo cognee-env /var/lib/cognee/venv/bin/cognee-cli search -t CHUNKS -d finance -k 15 -f simple "GoDaddy charge"
```

`kb-search` runs two retrieval arms and fuses them with reciprocal rank
fusion: semantic (pgvector cosine over an HNSW index, query embedded with the
Qwen3-Embedding instruction prefix) and lexical (Postgres full-text over a GIN
index). The lexical arm makes rare terms, names, and one-word queries land; the
semantic arm covers paraphrase. The default output is eight short
`[dataset] file: excerpt` lines.

Hermes uses structured, longer excerpts:

```sh
kb-search --json --limit 8 --excerpt-chars 1200 "query"
```

Do not reintroduce ivfflat for the semantic arm: the original index shipped
with default `lists=100`/`probes=1` and measured 8% recall@10.

`cognee-cli search` flags: `-t` GRAPH_COMPLETION (default, one-shot answer
via the local brain) | RAG_COMPLETION | CHUNKS (raw retrieval, no LLM call) |
SUMMARIES | CYPHER; `-d` dataset(s): gmail, calendar, finance, forgejo,
downloads, loops, research; `-k` top-k; `-f json|pretty|simple`.

GRAPH_COMPLETION seeds from the top-k vector hits only (`top_k` defaults to
5 triplets), resolves that tiny neighborhood to text, and asks the local
brain, which answers strictly from context - so it says "No information
found" whenever the seeds miss, regardless of how rich the graph is. Pass
`-k 15` or higher for real questions, prefer `-t CHUNKS` for retrieval
(fast, no local-LLM bottleneck), and use `kb-graph resolve/neighbors/
connect/source` for relation questions - it walks the whole graph instead
of a 5-triplet neighborhood.

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
