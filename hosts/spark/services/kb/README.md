# Personal knowledge base

Local ingestion and hybrid retrieval for the personal knowledge base.

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

## Ingestion

The hourly timer runs the indexer automatically. Run it on demand with:

```sh
systemctl start kb-ingest
```

Each run performs a full reload of `kb_vec`, then recreates its HNSW and
full-text indexes.

## Search

```sh
kb-search "what does the neovim wiki say about LSP configuration?"
kb-search --json --limit 8 --excerpt-chars 1200 "query"
```

`kb-search` fuses semantic pgvector results and Postgres full-text results with
reciprocal rank fusion. The default output is eight short
`[dataset] file: excerpt` lines.

Do not reintroduce ivfflat. The original index used its defaults and measured
8% recall at 10. HNSW is near-exact at the current index size.
