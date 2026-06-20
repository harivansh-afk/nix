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
  ];

  # gmail connector: recent messages -> staging/gmail/<id>.md (headers + snippet).
  gmailConnector = pkgs.writeShellScript "kb-connector-gmail" ''
    set -uo pipefail
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
  ];

  # Connectors (run as rathi), plus point the existing kb-ingest service at the
  # staging area (the kb-ingest.environment attr merges with the service defined
  # in kb-ingest.nix).
  systemd.services =
    (mkConnector "gmail" gmailConnector)
    // (mkConnector "calendar" calendarConnector)
    // {
      kb-ingest.environment.KB_STAGING_DIR = stagingDir;
    };

  systemd.timers =
    # Connectors refresh hourly (light, gws API).
    (mkTimer "gmail" "hourly")
    // (mkTimer "calendar" "hourly")
    # Indexer runs nightly (cognify on the 120B is slow; keep it off the
    # daytime GPU). Incremental, so steady-state nights are cheap.
    // {
      # Indexer timer is DEFINED but NOT auto-enabled (wantedBy = []): cognify
      # extraction on the 120B is currently slow and can stall, so we do not run
      # it unattended yet. Connectors still populate staging cheaply. Run the
      # indexer manually (`systemctl start kb-ingest`), and once a fast cognify
      # model is wired, flip wantedBy to [ "timers.target" ].
      kb-ingest = {
        description = "Schedule nightly KB indexing";
        wantedBy = [ ];
        timerConfig = {
          OnCalendar = "*-*-* 04:00:00";
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };
    };
}
