{ pkgs, ... }:

# kb-graph-query.nix - `kb-graph` on PATH: read-only traversal of the Cognee
# knowledge graph, for the rathi user and Hermes.
#
# Sibling to kb-ingest.nix (which exposes `kb-search`, flat pgvector similarity).
# Where kb-search finds passages, kb-graph walks the *graph*: the entities Cognee
# extracted and the relations between them.
#
# Access: the knowledge graph lives in Kuzu (root-owned, /var/lib/cognee is 0750)
# AND is mirrored into Postgres (the `nodes` / `edges` tables + per-type pgvector
# collections). This tool reads ONLY the Postgres mirror over loopback, with the
# same low-value cognee creds kb-search already uses. So it needs no root, takes
# no Kuzu write lock (the nightly cognify in kb-graph.nix keeps that), and works
# under Hermes' NoNewPrivileges sandbox where sudo is unavailable.
#
# The four subcommands (resolve / neighbors / connect / source) and the reasoning
# contract are documented for agents in dots/hermes/TOOLS.md.

let
  kbDotsDir = "${../../dots/kb}";

  # Same dedicated python as kb-search: psycopg2 + stdlib urllib only, NOT the
  # root-only cognee venv, so `kb-graph` runs unprivileged for rathi / Hermes.
  kbPython = pkgs.python3.withPackages (ps: [ ps.psycopg2 ]);

  kbGraphBin = pkgs.writeShellScriptBin "kb-graph" ''
    set -euo pipefail
    exec ${kbPython}/bin/python "${kbDotsDir}/kb_graph.py" "$@"
  '';
in
{
  environment.systemPackages = [ kbGraphBin ];
}
