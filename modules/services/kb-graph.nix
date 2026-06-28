{ pkgs, ... }:

# kb-graph.nix - Scheduled Cognee LLM knowledge-graph build + render.
#
# Re-lights the Cognee GraphRAG path that was dropped in #222 (it was too slow
# on the old 120B brain). It is viable again on the faster Qwen3.6 brain served
# by inference.nix at 127.0.0.1:18080/v1.
#
# Daily, off-hours (04:00), low-priority: it globs the normalized markdown the
# connectors stage under /var/lib/kb/staging, feeds each doc to cognee.add()
# (content-hash dedupe makes re-adds cheap and the timer idempotent), runs
# cognee.cognify() to extract the LLM knowledge graph (stored in the embedded
# Kuzu engine), and renders the graph to a self-contained D3 HTML.
#
# Cost note: a 20-doc sample cognified in ~7.6min (324 nodes / 537 edges, ~16
# LLM extraction calls/doc serialized at llama.cpp --parallel 1). The full
# first build over ~487 staged docs is estimated multi-hour, hence off-hours;
# incremental runs are cheap thanks to dedupe. Follow-up: raising llama.cpp
# --parallel would parallelize extraction and cut build time (needs measuring).
#
# NOT exposed on the network: the rendered index.html lives world-readable on
# disk and the user tunnels to the box to view it. No Caddy/tailscale/ports.

let
  # Where the connectors (kb-ingestion.nix) stage normalized markdown.
  stagingDir = "/var/lib/kb/staging";
  # Output dir for the rendered graph (world-readable so a tunnel can view it).
  graphDir = "/var/lib/kb/graph";
  graphHtml = "${graphDir}/index.html";

  # The build script. It deliberately does NOT set LLM_MODEL / providers: it is
  # run via the `cognee-env` wrapper (knowledge-base.nix), so it inherits the
  # fully-local Cognee config (including the live brain alias) from that env.
  buildScript = pkgs.writeText "kb-graph-build.py" ''
    import asyncio
    import glob
    import os
    import time

    import cognee

    STAGING = ${builtins.toJSON stagingDir}
    GRAPH_HTML = ${builtins.toJSON graphHtml}


    async def main() -> None:
        start = time.monotonic()
        paths = sorted(glob.glob(os.path.join(STAGING, "**", "*.md"), recursive=True))

        added = 0
        for path in paths:
            with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
            if not text.strip():
                continue
            # add() dedupes by content hash, so unchanged docs are cheap.
            await cognee.add(text)
            added += 1

        # Build the LLM knowledge graph incrementally (no prune: keep prior work).
        await cognee.cognify()

        os.makedirs(os.path.dirname(GRAPH_HTML), exist_ok=True)
        await cognee.visualize_graph(GRAPH_HTML)

        elapsed = time.monotonic() - start
        print(f"kb-graph: cognified {added} docs in {elapsed:.1f}s -> {GRAPH_HTML}")


    asyncio.run(main())
  '';
in
{
  # World-readable output dir so the user can tunnel in and open index.html.
  systemd.tmpfiles.rules = [
    "d ${graphDir} 0755 root root -"
  ];

  # ---------------------------------------------------------------------------
  # kb-graph: oneshot Cognee cognify + render.
  #
  # Runs as root because the cognee venv and state (/var/lib/cognee) are
  # root-owned. oneshot means systemd will not start a second run while one is
  # in flight, which keeps the single-writer Kuzu graph lock happy.
  # ---------------------------------------------------------------------------
  systemd.services.kb-graph = {
    description = "Cognee knowledge-graph build (cognify) + render";
    # Ordering only; the timer triggers it. If these are down at 04:00 the build
    # will fail and Persistent retries on next boot.
    after = [
      "network.target"
      "postgresql.service"
      "cognee-setup.service"
      "llama-cpp-embed.service"
      "llama-cpp.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";

      # Invoke via the cognee-env wrapper on PATH so the script inherits the
      # fully-local Cognee config (LLM/embeddings/pg/kuzu) from knowledge-base.nix.
      ExecStart = "/run/current-system/sw/bin/cognee-env ${buildScript}";

      # First build is multi-hour; give it plenty of headroom.
      TimeoutStartSec = "6h";

      # Low priority: this is best-effort background work that must yield to the
      # interactive brain. Nice + idle-ish IO, but not so aggressive it starves.
      Nice = 15;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "kb-graph";
    };
  };

  systemd.timers.kb-graph = {
    description = "Run kb-graph daily, off-hours";
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "20min";
    };
    wantedBy = [ "timers.target" ];
  };
}
