{ pkgs, ... }:

# kb-graph.nix - Scheduled Cognee LLM knowledge-graph build + render.
#
# Re-lights the Cognee GraphRAG path that was dropped in #222 (it was too slow
# on the old 120B brain). It is viable again on the faster Qwen3.6 brain served
# by inference.nix at 127.0.0.1:18080/v1.
#
# Daily, off-hours (04:00), low-priority: it globs the normalized markdown the
# connectors stage under /var/lib/kb/staging, then organizes the graph by
# ingester (issue #247): each doc is added into a dataset named for its source
# (gmail, calendar, forgejo, finance, ...) and tagged with that source via
# node_set, and cognify runs per-dataset (content-hash dedupe makes re-adds
# cheap and the timer idempotent). High-value domains (finance / calendar /
# gmail) cognify against a small RDF/XML ontology so their entities snap onto a
# consistent type vocabulary. The result is the LLM knowledge graph (stored in
# the embedded Kuzu engine), rendered to a self-contained D3 HTML.
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

  # Domain ontology (Lever 3) for the high-value sources. cognee 1.1.3's only
  # ontology resolver is the RDFLib one (cognee.modules.ontology), which expects
  # an RDF/XML (OWL) file: it fuzzy-matches extracted entity names against these
  # classes so the LLM graph snaps onto a consistent type vocabulary instead of
  # ad-hoc per-doc types. The resolver is global (one vocabulary across all
  # entities), so this single file unions the finance / calendar / email domains.
  ontologyOwl = pkgs.writeText "kb-graph-ontology.owl" ''
    <?xml version="1.0"?>
    <rdf:RDF
        xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
        xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
        xmlns:owl="http://www.w3.org/2002/07/owl#"
        xml:base="http://harivan.sh/kb#"
        xmlns="http://harivan.sh/kb#">

      <owl:Ontology rdf:about="http://harivan.sh/kb"/>

      <!-- finance domain -->
      <owl:Class rdf:about="#Merchant"/>
      <owl:Class rdf:about="#Account"/>
      <owl:Class rdf:about="#Transaction"/>
      <owl:Class rdf:about="#Category"/>
      <owl:ObjectProperty rdf:about="#charged_to">
        <rdfs:domain rdf:resource="#Transaction"/>
        <rdfs:range rdf:resource="#Account"/>
      </owl:ObjectProperty>
      <owl:ObjectProperty rdf:about="#purchased_at">
        <rdfs:domain rdf:resource="#Transaction"/>
        <rdfs:range rdf:resource="#Merchant"/>
      </owl:ObjectProperty>
      <owl:ObjectProperty rdf:about="#categorized_as">
        <rdfs:domain rdf:resource="#Transaction"/>
        <rdfs:range rdf:resource="#Category"/>
      </owl:ObjectProperty>

      <!-- calendar domain -->
      <owl:Class rdf:about="#Event"/>
      <owl:Class rdf:about="#Person"/>
      <owl:Class rdf:about="#Location"/>

      <!-- email domain -->
      <owl:Class rdf:about="#Org"/>
      <owl:Class rdf:about="#Thread"/>
    </rdf:RDF>
  '';

  # The build script. It deliberately does NOT set LLM_MODEL / providers: it is
  # run via the `cognee-env` wrapper (knowledge-base.nix), so it inherits the
  # fully-local Cognee config (including the live brain alias) from that env.
  buildScript = pkgs.writeText "kb-graph-build.py" ''
    import asyncio
    import glob
    import os
    import time

    import cognee
    from cognee.modules.ontology.matching_strategies import FuzzyMatchingStrategy
    from cognee.modules.ontology.rdf_xml.RDFLibOntologyResolver import (
        RDFLibOntologyResolver,
    )

    STAGING = ${builtins.toJSON stagingDir}
    GRAPH_HTML = ${builtins.toJSON graphHtml}
    ONTOLOGY_OWL = ${builtins.toJSON ontologyOwl}

    # Datasets the domain ontology (Lever 3) applies to. The other sources
    # (forgejo, downloads, research) cognify with no ontology - their entities
    # are too heterogeneous to pin to a fixed vocabulary.
    ONTOLOGY_SOURCES = {"finance", "calendar", "gmail"}


    def source_of(path: str) -> str:
        """Top-level staging source: the dir right after STAGING.

        e.g. /var/lib/kb/staging/finance/transactions/x.md -> "finance",
             /var/lib/kb/staging/gmail/y.md                 -> "gmail".
        """
        rel = os.path.relpath(path, STAGING)
        head = rel.split(os.sep, 1)[0]
        return head if head not in ("", ".", "..") else "uncategorized"


    async def main() -> None:
        start = time.monotonic()
        paths = sorted(glob.glob(os.path.join(STAGING, "**", "*.md"), recursive=True))

        # Lever 1 + 2: route each doc into a dataset named for its ingester and
        # tag every node it produces with that source via node_set, so the graph
        # can be filtered / colored by ingester. add() dedupes by content hash,
        # so unchanged docs are cheap and re-runs stay idempotent.
        added = 0
        sources = set()
        for path in paths:
            with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
            if not text.strip():
                continue
            source = source_of(path)
            sources.add(source)
            await cognee.add(text, dataset_name=source, node_set=[source])
            added += 1

        # Lever 3: build the RDFLib ontology resolver once and pass it to cognify
        # for the high-value domains. cognify takes a per-call `config` dict, so
        # ontology-backed sources cognify with the resolver and the rest plain.
        resolver = RDFLibOntologyResolver(
            ontology_file=ONTOLOGY_OWL,
            matching_strategy=FuzzyMatchingStrategy(),
        )
        ontology_config = {"ontology_config": {"ontology_resolver": resolver}}

        # Cognify per-dataset (no prune: keep prior work) so a failure in one
        # source does not abort the others and each can carry its own ontology.
        for source in sorted(sources):
            cfg = ontology_config if source in ONTOLOGY_SOURCES else None
            await cognee.cognify(datasets=source, config=cfg)

        os.makedirs(os.path.dirname(GRAPH_HTML), exist_ok=True)
        await cognee.visualize_graph(GRAPH_HTML)

        elapsed = time.monotonic() - start
        print(
            f"kb-graph: cognified {added} docs across {len(sources)} sources "
            f"in {elapsed:.1f}s -> {GRAPH_HTML}"
        )


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
