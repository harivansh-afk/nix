{ pkgs, ... }:
# kb-ingestion.nix - scheduled ingestion systems (systemd timers).
#
# Architecture: decouple "get the data" from "index the data".
#   connectors (per source) --> /var/lib/kb/staging/<source>/*.md --> kb-ingest
# Each connector is a small timer-driven job that pulls from an app API and
# writes normalized markdown into the staging area. The existing kb-ingest
# service (modules/services/kb-ingest.nix) then indexes staging + the local
# corpus into Cognee, incrementally (denylist + content-hash state still apply).
#
# Connectors run as rathi (they use the user's `gws` Google Workspace creds);
# the indexer runs as root (the Cognee venv/state under /var/lib/cognee is
# root-owned). Staging is rathi-owned so connectors can write and root can read.
#
# gws auth: until `gws` is authenticated (browser OAuth), the connectors detect
# the failure and exit 0 cleanly (no spam, no partial writes). They become
# productive the moment auth is in place - no rebuild needed.
let
  user = "rathi";
  group = "users";
  stagingDir = "/var/lib/kb/staging";
  gws = "/run/current-system/sw/bin/gws";

  connectorPath = [
    pkgs.jq
    pkgs.coreutils
    pkgs.gnused
    pkgs.curl
  ];

  # Python with the document-extraction libs the downloads connector needs:
  # pymupdf (fitz) for pdf, python-docx for docx, openpyxl for xlsx, stdlib for
  # txt. Attr names verified against nixpkgs python3Packages.
  downloadsPython = pkgs.python3.withPackages (ps: [
    ps.pymupdf
    ps.python-docx
    ps.openpyxl
  ]);

  # downloads connector: extract text from ~/Documents/Downloads personal docs
  # -> staging/downloads/*.md (frontmatter + body, content-hash dedupe). The
  # extractor (dots/kb/downloads_connector.py) enforces the hard privacy
  # denylist in code; see that file and CLAUDE.md.
  downloadsConnector = pkgs.writeShellScript "kb-connector-downloads" ''
    set -uo pipefail
    exec ${downloadsPython}/bin/python ${../../dots/kb/downloads_connector.py}
  '';

  # gws needs the OAuth client (from the gws.env sops secret, exposed under the
  # GOOGLE_WORKSPACE_CLI_* names this gws build expects) plus the user token. The
  # token is exported to a sops-managed credentials file for deterministic, keyring-
  # free use under systemd. Sourced at the top of each gws connector.
  gwsEnvSetup = ''
    set -a
    . /run/secrets/gws.env 2>/dev/null || true
    set +a
    export GOOGLE_WORKSPACE_CLI_CLIENT_ID="''${GWS_CLIENT_ID:-}"
    export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="''${GWS_CLIENT_SECRET:-}"
    [ -r /run/secrets/gws-credentials.json ] \
      && export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/run/secrets/gws-credentials.json
  '';

  # forgejo connector: own repos -> staging/forgejo/ (READMEs + open issues).
  # Token comes from the existing forgejo-token sops secret (loopback-safe).
  forgejoConnector = pkgs.writeShellScript "kb-connector-forgejo" ''
    set -uo pipefail
    out="${stagingDir}/forgejo"
    mkdir -p "$out"
    base="https://git.harivan.sh/api/v1"
    tok=$(cat /run/secrets/forgejo-token.env 2>/dev/null) || {
      echo "no forgejo token; skipping"; exit 0
    }
    auth="Authorization: token $tok"
    repos=$(curl -fsS -H "$auth" "$base/user/repos?limit=50" 2>/dev/null \
      | jq -r '.[].full_name' 2>/dev/null) || {
      echo "forgejo API unreachable; skipping"; exit 0
    }
    n=0
    for r in $repos; do
      safe=$(printf '%s' "$r" | tr '/' '_')
      readme=$(curl -fsS -H "$auth" "$base/repos/$r/contents/README.md" 2>/dev/null \
        | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null) || readme=""
      [ -n "$readme" ] && printf '# %s (README)\n\n%s\n' "$r" "$readme" > "$out/''${safe}_README.md"
      issues=$(curl -fsS -H "$auth" "$base/repos/$r/issues?state=open&limit=50&type=issues" 2>/dev/null \
        | jq -r '.[] | "## #\(.number) \(.title)\n\n\(.body // "")\n"' 2>/dev/null) || issues=""
      [ -n "$issues" ] && printf '# %s (open issues)\n\n%s\n' "$r" "$issues" > "$out/''${safe}_issues.md"
      n=$((n + 1))
    done
    echo "forgejo: synced $n repo(s) to $out"
  '';

  # gmail connector: recent messages -> staging/gmail/<id>.md (headers + snippet).
  gmailConnector = pkgs.writeShellScript "kb-connector-gmail" ''
    set -uo pipefail
    ${gwsEnvSetup}
    out="${stagingDir}/gmail"
    mkdir -p "$out"
    if ! ${gws} gmail users getProfile --params '{"userId":"me"}' >/dev/null 2>&1; then
      echo "gws not authenticated; skipping gmail ingest"; exit 0
    fi
    ids=$(${gws} gmail users messages list --params '{"userId":"me","maxResults":50}' \
      2>/dev/null | jq -r '.messages[]?.id' 2>/dev/null) || ids=""
    n=0
    for id in $ids; do
      f="$out/$id.md"
      [ -f "$f" ] && continue
      msg=$(${gws} gmail users messages get \
        --params "{\"userId\":\"me\",\"id\":\"$id\",\"format\":\"full\"}" 2>/dev/null) || continue
      subj=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="Subject") | .value' 2>/dev/null | head -1)
      frm=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="From") | .value' 2>/dev/null | head -1)
      dt=$(printf '%s' "$msg" | jq -r '.payload.headers[]? | select(.name=="Date") | .value' 2>/dev/null | head -1)
      snip=$(printf '%s' "$msg" | jq -r '.snippet // ""' 2>/dev/null)
      {
        printf '# %s\n\n' "''${subj:-(no subject)}"
        printf -- '- From: %s\n- Date: %s\n- Source: gmail\n\n' "$frm" "$dt"
        printf '%s\n' "$snip"
      } > "$f"
      n=$((n + 1))
    done
    echo "gmail: wrote $n new message(s) to $out"
  '';

  # calendar connector: next 90 days of events -> staging/calendar/<id>.md.
  calendarConnector = pkgs.writeShellScript "kb-connector-calendar" ''
    set -uo pipefail
    ${gwsEnvSetup}
    out="${stagingDir}/calendar"
    mkdir -p "$out"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    future=$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%SZ)
    params=$(printf '{"calendarId":"primary","timeMin":"%s","timeMax":"%s","singleEvents":true,"orderBy":"startTime","maxResults":250}' "$now" "$future")
    events=$(${gws} calendar events list --params "$params" 2>/dev/null) || {
      echo "gws not authenticated or calendar unavailable; skipping"; exit 0
    }
    count=$(printf '%s' "$events" | jq '.items | length' 2>/dev/null) || count=0
    [ "$count" = "null" ] && count=0
    i=0
    while [ "$i" -lt "$count" ]; do
      ev=$(printf '%s' "$events" | jq ".items[$i]")
      id=$(printf '%s' "$ev" | jq -r '.id')
      summary=$(printf '%s' "$ev" | jq -r '.summary // "(no title)"')
      start=$(printf '%s' "$ev" | jq -r '.start.dateTime // .start.date // ""')
      end=$(printf '%s' "$ev" | jq -r '.end.dateTime // .end.date // ""')
      loc=$(printf '%s' "$ev" | jq -r '.location // ""')
      desc=$(printf '%s' "$ev" | jq -r '.description // ""')
      {
        printf '# %s\n\n' "$summary"
        printf -- '- Start: %s\n- End: %s\n- Location: %s\n- Source: calendar\n\n' "$start" "$end" "$loc"
        printf '%s\n' "$desc"
      } > "$out/$id.md"
      i=$((i + 1))
    done
    echo "calendar: wrote $count event(s) to $out"
  '';

  # A connector service + hourly timer that runs as the user (gws creds).
  mkConnector = name: exec: {
    "kb-connector-${name}" = {
      description = "KB connector: ${name} -> staging";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = connectorPath;
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = exec;
      };
    };
  };

  mkTimer = name: onCalendar: {
    "kb-connector-${name}" = {
      description = "Schedule KB connector: ${name}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
in
{
  # Staging area, owned by rathi so connectors write and root indexer reads.
  systemd.tmpfiles.rules = [
    "d /var/lib/kb 0755 ${user} ${group} -"
    "d ${stagingDir} 0755 ${user} ${group} -"
    "d ${stagingDir}/gmail 0755 ${user} ${group} -"
    "d ${stagingDir}/calendar 0755 ${user} ${group} -"
    "d ${stagingDir}/forgejo 0755 ${user} ${group} -"
    "d ${stagingDir}/downloads 0755 ${user} ${group} -"
  ];

  # Connectors (run as rathi), plus point the existing kb-ingest service at the
  # staging area (the kb-ingest.environment attr merges with the service defined
  # in kb-ingest.nix).
  systemd.services =
    (mkConnector "gmail" gmailConnector)
    // (mkConnector "calendar" calendarConnector)
    // (mkConnector "forgejo" forgejoConnector)
    // (mkConnector "downloads" downloadsConnector)
    // {
      kb-ingest.environment.KB_STAGING_DIR = stagingDir;
    };

  systemd.timers =
    # Connectors refresh hourly (light API calls).
    (mkTimer "gmail" "hourly")
    // (mkTimer "calendar" "hourly")
    // (mkTimer "forgejo" "hourly")
    # Downloads change slowly; daily is plenty (and extraction is heavier).
    // (mkTimer "downloads" "daily")
    # Indexer runs hourly: the vector reindex (embeddings -> pgvector, no LLM)
    # is ~15s for a few hundred docs, so it is cheap to run often and keeps the
    # KB fresh shortly after the connectors collect new docs.
    // {
      kb-ingest = {
        description = "Schedule hourly KB vector reindex";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5min";
        };
      };
    };
}
