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
# auth, so the HN mission is fully self-contained. The X mission drives the
# native local `browse` CLI (browser-use.nix: headless Chromium + local brain,
# DOM mode) and no-ops cleanly until a logged-in X session is supplied
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
    # The x mission shells out to the native `browse` CLI (browser-use.nix),
    # which is also installed system-wide via environment.systemPackages.
    pkgs.gnugrep
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
  # Mission: x (X / Twitter) - GATED on a logged-in X session.
  # X has no free read API, so this mission drives the NATIVE local `browse` CLI
  # (browser-use.nix: headless Chromium + local brain, DOM mode) to gather
  # candidate posts, then distills them with the brain. No cloud API.
  #
  # X requires a logged-in browser session. Supply one of:
  #   - a persistent profile: log in once with a headful browse against the
  #     browser-use profile dir (/var/lib/browser-use/profile); or
  #   - a cookies/storage_state json at the sops secret "x-session.json",
  #     exported here as BROWSER_USE_STORAGE_STATE.
  # Until a session marker file exists at $X_SESSION_MARKER (default
  # /var/lib/browser-use/x-session-ok) OR BROWSER_USE_STORAGE_STATE is set, the
  # mission no-ops (logs + exit 0), exactly like the gws connectors when
  # unauthenticated. The `browse` wrapper handles Chromium + the local brain.
  # ---------------------------------------------------------------------------
  xMission = pkgs.writeShellScript "kb-research-x" ''
    ${brainHelpers "x"}

    marker="''${X_SESSION_MARKER:-/var/lib/browser-use/x-session-ok}"
    if [ ! -e "$marker" ] && [ -z "''${BROWSER_USE_STORAGE_STATE:-}" ]; then
      echo "x: skipping, no X session (no $marker and BROWSER_USE_STORAGE_STATE unset)"; exit 0
    fi
    if ! command -v browse >/dev/null 2>&1; then
      echo "x: skipping, browse CLI not available"; exit 0
    fi

    # --- Gather candidate posts via the native local `browse` agent. ---------
    # Ask the agent to return a plain text list of "<gist> | <url>" lines. Any
    # failure (no login, agent error, timeout) no-ops cleanly.
    task='Open x.com (you are already logged in), read the home/following or explore timeline, and find the ~20 most interesting recent posts about AI, systems, and technology. Return ONLY a plain text list, one post per line, formatted "<one-line gist> | <post url>". Do not add commentary.'
    cands=$(browse "$task" 2>/dev/null) || {
      echo "x: browse agent failed; skipping"; exit 0
    }
    if [ -z "$cands" ]; then
      echo "x: no candidate posts from browse; skipping"; exit 0
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
  # `afterUnits` lists extra units to order after / want (e.g. browser-use-setup).
  mkMission = name: exec: passEnv: afterUnits: {
    "kb-research-${name}" = {
      description = "KB research mission: ${name} -> staging";
      after = [ "network-online.target" ] ++ afterUnits;
      wants = [ "network-online.target" ] ++ afterUnits;
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
    (mkMission "hackernews" hackernewsMission [ ] [ ])
    # The x mission shells out to `browse`; ensure its venv is built first.
    // (mkMission "x" xMission [ "BROWSER_USE_STORAGE_STATE" ] [ "browser-use-setup.service" ]);

  systemd.timers =
    # Daily distillation runs; cheap (a handful of brain calls).
    (mkTimer "hackernews" "*-*-* 08:00:00") // (mkTimer "x" "*-*-* 08:30:00");
}
