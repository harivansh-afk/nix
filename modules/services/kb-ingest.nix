{
  pkgs,
  ...
}:

# kb-ingest.nix - Personal knowledge base ingestion service + search tool.
#
# Provides:
#   (a) kb-search wrapper on PATH - calls the cognee venv python with kb-search.
#   (b) systemd oneshot service kb-ingest - runs ingest.py via the cognee env.
#       DISABLED by default (wantedBy = []); trigger manually:
#           systemctl start kb-ingest
#
# Optional timer (commented out below) can be enabled to run on a schedule.
#
# INTEGRATION TODO: "cognee-env" is expected to be a wrapper binary on PATH
# that launches the cognee uv venv python with all local-provider env vars set
# (LLM at 127.0.0.1:18080/v1, embeddings at 127.0.0.1:18200/v1, pgvector).
# Once the KB backend module finalises the venv layout, replace the string
# "cognee-env" below with the absolute path to that binary if it is not on
# the system PATH (e.g. "/var/lib/cognee/venv/bin/cognee-env" or similar).

let
  # The dots/kb scripts, pulled from the nix store (reproducible, world-readable
  # so both the root ingest service and the rathi-run kb-search can exec them).
  kbDotsDir = "${../../dots/kb}";

  # Dedicated python for kb_vec.py (only needs psycopg2 + stdlib urllib). Avoids
  # the root-only cognee venv (/var/lib/cognee/venv is 0750), so kb-search works
  # for the rathi user / Hermes too, not just root.
  kbPython = pkgs.python3.withPackages (ps: [ ps.psycopg2 ]);

  # kb-search wrapper: plain vector search over pgvector using the local
  # embedding model (no LLM, no knowledge graph). cognee-env is reused only for
  # its venv python (psycopg2 + libs); the script hardcodes the embed endpoint
  # and pg creds. Arguments are the query string.
  kbSearchBin = pkgs.writeShellScriptBin "kb-search" ''
    set -euo pipefail
    if [ $# -eq 0 ]; then
      echo "Usage: kb-search <query>" >&2
      exit 2
    fi
    exec ${kbPython}/bin/python "${kbDotsDir}/kb_vec.py" search "$@"
  '';

in
{
  # ---------------------------------------------------------------------------
  # (a) kb-search on PATH
  # ---------------------------------------------------------------------------
  environment.systemPackages = [ kbSearchBin ];

  # ---------------------------------------------------------------------------
  # (b) kb-ingest systemd oneshot service
  # ---------------------------------------------------------------------------
  systemd.services.kb-ingest = {
    description = "Personal KB vector index (embeddings -> pgvector)";

    # Started by kb-ingest.timer (hourly, enabled in kb-ingestion.nix). The
    # vector reindex is fast (~15s for a few hundred docs), so hourly is cheap.
    wantedBy = [ ];
    # Manual trigger; ordering only applies if these are up when it runs.
    after = [
      "network.target"
      "postgresql.service"
      "cognee-setup.service"
      "llama-cpp-embed.service"
      "llama-cpp.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      # Runs as root to match the root-owned /var/lib/cognee state + venv
      # created by knowledge-base.nix. The dir is provisioned there via
      # tmpfiles, so no StateDirectory (which would chown it) here.
      User = "root";

      # Working directory; script locates denylist.txt relative to itself.
      WorkingDirectory = kbDotsDir;

      # Vector reindex: embed all staged + corpus docs into pgvector. Fast (no
      # LLM), so a full reindex each run is fine and keeps it simple/idempotent.
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${kbPython}/bin/python ${kbDotsDir}/kb_vec.py ingest'";

      # Safety: do not allow writes outside the state dir.
      ReadWritePaths = [ "/var/lib/cognee" ];

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "kb-ingest";
    };
  };

  # ---------------------------------------------------------------------------
  # Optional timer (disabled by default - uncomment and nixos-rebuild to enable)
  # ---------------------------------------------------------------------------
  #
  # systemd.timers.kb-ingest = {
  #   description = "Run kb-ingest nightly";
  #   timerConfig = {
  #     OnCalendar = "daily";
  #     Persistent = true;
  #     RandomizedDelaySec = "30min";
  #   };
  #   wantedBy = [ "timers.target" ];
  # };
}
