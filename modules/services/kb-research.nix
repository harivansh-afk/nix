{ pkgs, ... }:
# kb-research.nix - scheduled "research missions" that distill the most
# interesting items from a source into the KB (latest-first).
#
# A mission = { name, schedule, gather, goalPrompt }. For each mission we define
# a systemd oneshot service (runs as rathi) + timer that:
#   1. Gathers candidate items from the source (the per-mission `gather` step).
#   2. Calls the local brain (127.0.0.1:18080/v1/chat/completions, qwen3.6-35b-a3b)
#      with `goalPrompt` to pick + summarize the most intriguing items
#      (gist + why-interesting + link).
#   3. Writes a TIMESTAMPED markdown note to
#         /var/lib/kb/staging/research/<mission>/<ISO8601-UTC>.md
#      The timestamp filename gives latest-first ordering by name. The existing
#      hourly kb-ingest (modules/services/kb-ingestion.nix) then embeds it into
#      pgvector - this module does NOT touch the kb-ingest hot path.
#
# Missions run as rathi (staging is rathi-owned). The brain runs locally with no
# auth, so the HN mission is fully self-contained. The X mission needs a
# browser-use API key and no-ops cleanly until BROWSER_USE_API_KEY is set
# (mirroring how the gws connectors no-op when unauthenticated).
let
  user = "rathi";
  group = "users";
  researchDir = "/var/lib/kb/staging/research";
  brainUrl = "http://127.0.0.1:18080/v1/chat/completions";
  brainModel = "qwen3.6-35b-a3b";

  missionPath = [
    pkgs.jq
    pkgs.coreutils
    pkgs.gnused
    pkgs.curl
  ];

  # Shared helper sourced at the top of every mission script. Provides:
  #   brain "<system prompt>" "<user content>"  -> prints the model's text reply
  #     (or empty on any failure - callers must handle an empty result).
  #   note_path                                 -> ISO8601-UTC .md path for this run
  #   write_note <mission> <source> <urls-csv> <tags-csv> <body-file>
  #     -> writes the timestamped note with frontmatter to staging/research/<mission>/.
  brainHelpers = mission: ''
    set -uo pipefail
    runts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    out="${researchDir}/${mission}"
    mkdir -p "$out"

    # brain <system> <user> -> model text reply on stdout (empty on failure).
    brain() {
      local sys="$1" usr="$2" req resp
      req=$(jq -n --arg m "${brainModel}" --arg s "$sys" --arg u "$usr" \
        '{model:$m, temperature:0.4, messages:[{role:"system",content:$s},{role:"user",content:$u}]}') || return 0
      resp=$(curl -fsS --max-time 300 -H 'Content-Type: application/json' \
        -d "$req" "${brainUrl}" 2>/dev/null) || { echo "brain unreachable" >&2; return 0; }
      printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null
    }

    # write_note <source> <urls-csv> <tags-csv> <body-file>
    write_note() {
      local source="$1" urls="$2" tags="$3" bodyfile="$4"
      local f="$out/$runts.md"
      {
        printf -- '---\n'
        printf 'mission: %s\n' "${mission}"
        printf 'run: %s\n' "$runts"
        printf 'source: %s\n' "$source"
        printf 'item_urls: %s\n' "$urls"
        printf 'tags: %s\n' "$tags"
        printf -- '---\n\n'
        cat "$bodyfile"
      } > "$f"
      echo "${mission}: wrote $f"
    }
  '';

  # ---------------------------------------------------------------------------
  # Mission: hackernews - daily, no key required.
  # Pull the HN front page (Algolia), take the top ~30, and have the brain pick
  # the ~5 most intriguing stories with a one-line why-each.
  # ---------------------------------------------------------------------------
  hackernewsMission = pkgs.writeShellScript "kb-research-hackernews" ''
    ${brainHelpers "hackernews"}
    api="https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30"
    stories=$(curl -fsS --max-time 60 "$api" 2>/dev/null) || {
      echo "hackernews: HN Algolia unreachable; skipping"; exit 0
    }
    # Compact candidate list for the prompt: title, points, url, HN discussion.
    cands=$(printf '%s' "$stories" | jq -r '
      .hits[]? | select(.title != null) |
      "- \(.title) (\(.points // 0) pts) | url: \(.url // ("https://news.ycombinator.com/item?id=" + .objectID)) | hn: https://news.ycombinator.com/item?id=\(.objectID)"
    ' 2>/dev/null) || cands=""
    if [ -z "$cands" ]; then
      echo "hackernews: no candidate stories; skipping"; exit 0
    fi
    # Collect all candidate URLs for the frontmatter (article URL where present).
    urls=$(printf '%s' "$stories" | jq -r '
      [.hits[]? | (.url // ("https://news.ycombinator.com/item?id=" + .objectID))] | join(", ")
    ' 2>/dev/null) || urls=""

    sys="You are a sharp tech-news curator for a single expert reader. From the Hacker News front page below, pick the 5 MOST intriguing items - favour deep/novel/technical over routine product news. For each, output a markdown section: '## <title>' then a one-line gist, a one-line 'Why interesting:', and a 'Link:' line with the article URL (use the HN discussion link only if no article URL). Output only those 5 sections, nothing else."
    body=$(brain "$sys" "$cands")
    if [ -z "$body" ]; then
      echo "hackernews: brain returned nothing; skipping"; exit 0
    fi
    tmp=$(mktemp)
    printf '# Hacker News - most intriguing (%s)\n\n%s\n' "$runts" "$body" > "$tmp"
    write_note "hackernews" "$urls" "research, hackernews, tech" "$tmp"
    rm -f "$tmp"
  '';

  # ---------------------------------------------------------------------------
  # Mission: x (X / Twitter) - GATED on BROWSER_USE_API_KEY.
  # X has no free read API, so this mission drives the browser-use cloud API to
  # gather candidate posts, then distills them with the brain.
  #
  # To enable: set BROWSER_USE_API_KEY in the service environment (e.g. via a
  # sops secret exported into the unit, mirroring forgejo-token), then this job
  # becomes productive with no rebuild of the script needed. Until then it
  # no-ops (logs + exit 0), exactly like the gws connectors when unauthenticated.
  #
  # browser-use API (see dots/hermes/TOOLS.md):
  #   POST https://api.browser-use.com/api/v3/tasks  with header
  #   X-Browser-Use-API-Key: $BROWSER_USE_API_KEY  and a task describing what to
  #   collect from X (e.g. top posts on a topic), then poll the task for output.
  # ---------------------------------------------------------------------------
  xMission = pkgs.writeShellScript "kb-research-x" ''
    ${brainHelpers "x"}
    if [ -z "''${BROWSER_USE_API_KEY:-}" ]; then
      echo "x: skipping: BROWSER_USE_API_KEY not set"; exit 0
    fi

    # --- Gather candidate posts via the browser-use cloud API. ---------------
    # Create a task asking browser-use to collect the most interesting recent
    # posts (return a plain text list of "<gist> | <url>" lines), then poll for
    # the finished output. Any failure no-ops cleanly.
    api="https://api.browser-use.com/api/v3"
    auth="X-Browser-Use-API-Key: ''${BROWSER_USE_API_KEY}"
    task='Open x.com, find the ~20 most interesting recent posts about AI, systems, and technology from the home/explore timeline, and return them as a plain text list, one per line, formatted "<one-line gist> | <post url>".'
    created=$(curl -fsS --max-time 60 -H "$auth" -H 'Content-Type: application/json' \
      -d "$(jq -n --arg t "$task" '{task:$t}')" "$api/tasks" 2>/dev/null) || {
      echo "x: browser-use API unreachable; skipping"; exit 0
    }
    task_id=$(printf '%s' "$created" | jq -r '.id // empty' 2>/dev/null)
    if [ -z "$task_id" ]; then
      echo "x: browser-use did not return a task id; skipping"; exit 0
    fi
    # Poll up to ~5 minutes for completion.
    cands=""; i=0
    while [ "$i" -lt 30 ]; do
      st=$(curl -fsS --max-time 30 -H "$auth" "$api/tasks/$task_id" 2>/dev/null) || break
      status=$(printf '%s' "$st" | jq -r '.status // empty' 2>/dev/null)
      case "$status" in
        finished|completed) cands=$(printf '%s' "$st" | jq -r '.output // empty' 2>/dev/null); break ;;
        failed|stopped) echo "x: browser-use task $status; skipping"; exit 0 ;;
      esac
      sleep 10
      i=$((i + 1))
    done
    if [ -z "$cands" ]; then
      echo "x: no candidate posts from browser-use; skipping"; exit 0
    fi

    # --- Distill with the brain. ---------------------------------------------
    sys="You are a sharp curator for a single expert reader. From the X/Twitter posts below, pick the 5 MOST intriguing - favour novel ideas and signal over hype. For each, output '## <short title>' then a one-line gist, a one-line 'Why interesting:', and a 'Link:' line with the post URL. Output only those 5 sections."
    body=$(brain "$sys" "$cands")
    if [ -z "$body" ]; then
      echo "x: brain returned nothing; skipping"; exit 0
    fi
    urls=$(printf '%s' "$cands" | grep -oE 'https?://[^ ]+' | paste -sd ', ' -)
    tmp=$(mktemp)
    printf '# X - most intriguing (%s)\n\n%s\n' "$runts" "$body" > "$tmp"
    write_note "x" "$urls" "research, x, twitter" "$tmp"
    rm -f "$tmp"
  '';

  # A mission service + timer (runs as the user; staging is rathi-owned).
  # `passEnv` lists env vars to inherit from the manager (for browser-use gating).
  mkMission = name: exec: passEnv: {
    "kb-research-${name}" = {
      description = "KB research mission: ${name} -> staging";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = missionPath;
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = exec;
        PassEnvironment = passEnv;
      };
    };
  };

  mkTimer = name: onCalendar: {
    "kb-research-${name}" = {
      description = "Schedule KB research mission: ${name}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = onCalendar;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };
in
{
  # Research staging dirs, rathi-owned so missions write and root indexer reads.
  systemd.tmpfiles.rules = [
    "d ${researchDir} 0755 ${user} ${group} -"
    "d ${researchDir}/hackernews 0755 ${user} ${group} -"
    "d ${researchDir}/x 0755 ${user} ${group} -"
  ];

  systemd.services =
    (mkMission "hackernews" hackernewsMission [ ])
    // (mkMission "x" xMission [ "BROWSER_USE_API_KEY" ]);

  systemd.timers =
    # Daily distillation runs; cheap (a handful of brain calls).
    (mkTimer "hackernews" "*-*-* 08:00:00") // (mkTimer "x" "*-*-* 08:30:00");
}
