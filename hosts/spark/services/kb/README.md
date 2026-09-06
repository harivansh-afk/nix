# Personal knowledge base

Disabled on Spark. The host no longer imports this module, so the embedding
server, model downloader, connector and ingestion services/timers, KB PostgreSQL
service, and `kb-search` are absent from the system configuration. Hermes's KB
plugin is disabled and its plugin/staging symlinks are removed on activation.

Existing PostgreSQL data, `/var/lib/kb`, `/var/lib/llama-cpp-embed`, and legacy
`/var/lib/cognee` data remain on disk. Disabling services does not delete them.
Hermes conversation memory and skills remain enabled.

The source below is retained for reference; re-enabling the KB requires an
explicit request and a configuration change.

## Files

| File | Purpose |
|------|---------|
| `kb_vec.py` | Hourly chunking, embedding, and hybrid vector/full-text retrieval |
| `downloads_connector.py` | Local document extraction into the staging directory |
| `default.nix` | Postgres, embeddings server, connectors, indexer, `kb-search` |
| `connectors/` | gmail, calendar and forgejo connector scripts |

## Architecture

Source connectors normalize Gmail, Calendar, Forgejo, and local downloads into
`/var/lib/kb/staging/<source>/`. The hourly indexer rebuilds the Postgres index
from that staging directory. It chunks documents, embeds them with the local
Qwen3-Embedding-0.6B server, and creates pgvector HNSW and Postgres full-text
indexes.

The indexer does not invoke an LLM. Search excludes the finance dataset by
default. Separate local-only workflows handle finance data.

## Denylist

The downloads connector never reads the directories listed in `DENYLIST` in
`downloads_connector.py` (security, finance-tax, travel-identity,
legal-business), and skips hidden files and directories.

## Ingestion when enabled

The hourly timer runs the indexer automatically. Run it on demand with:

```sh
systemctl start kb-ingest
```

Each run performs a full reload of `kb_vec`, then recreates its HNSW and
full-text indexes.

## Search when enabled

```sh
kb-search "what does the neovim wiki say about LSP configuration?"
kb-search --json --limit 8 --excerpt-chars 1200 "query"
```

`kb-search` fuses semantic pgvector results and Postgres full-text results with
reciprocal rank fusion. The default output is eight short
`[dataset] file: excerpt` lines.

Do not reintroduce ivfflat. The original index used its defaults and measured
8% recall at 10. HNSW is near-exact at the current index size.
