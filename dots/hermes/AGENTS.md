# Machine

Host: spark
Hardware: NVIDIA DGX Spark (GB10 Grace Blackwell, 128 GB unified memory, aarch64)
OS: NixOS
CUDA: 13

# Local LLM (primary reasoning model)

Endpoint: http://127.0.0.1:18080/v1 (OpenAI-compatible)
Model alias: nemotron-3-super-120b
Served by: llama.cpp
Use this for all local inference tasks.

# Knowledge Base

Backend: Cognee (semantic + graph search over indexed notes/docs)
Query via: kb-search tool/skill
Embeddings server: http://127.0.0.1:18200/v1
Vector store: Postgres + pgvector
Read freely. Never write to or modify the KB without being asked.

# Speech-to-Text

Service: Parakeet
Endpoint: http://127.0.0.1:6060 (OpenAI-compatible)

# Nix Config Repo

Path: /home/rathi/Documents/Git/nix
Canonical forge: Forgejo at git.harivan.sh (origin remote)
GitHub (github.com/harivansh-afk/nix) is a mirror only.
PRs: use the `tea` CLI, not GitHub.
To apply config changes: `just switch` (runs nh os switch for spark).
Rule: always ask before editing the nix repo.

# Tooling Preferences

- fd instead of find
- uv for Python (uv run, uv pip, uv venv - never bare pip)
- rg for text search
