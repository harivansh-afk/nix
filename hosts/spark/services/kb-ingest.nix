{
  pkgs,
  ...
}:

let
  kbDotsDir = "${../../../dots/kb}";
  kbPython = pkgs.python3.withPackages (ps: [ ps.psycopg2 ]);
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
  environment.systemPackages = [ kbSearchBin ];
  systemd.services.kb-ingest = {
    description = "Personal KB vector index (embeddings -> pgvector)";
    wantedBy = [ ];
    after = [
      "network.target"
      "kb-pg-setup.service"
      "llama-cpp-embed.service"
    ];
    requires = [
      "kb-pg-setup.service"
      "llama-cpp-embed.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "rathi";
      Group = "users";
      WorkingDirectory = kbDotsDir;
      ExecStart = "${pkgs.bash}/bin/bash -c 'exec ${kbPython}/bin/python ${kbDotsDir}/kb_vec.py ingest'";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "kb-ingest";
    };
  };

}
