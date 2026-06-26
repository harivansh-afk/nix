{ pkgs, ... }:
# hermes-feeds.nix - background knowledge "feeds" for the personal KB.
#
# This is the X/RSS scroller, automated: instead of Hari doom-scrolling for
# signal, timer-driven connectors pull content he cares about (local-LLM,
# NixOS, systems/infra, AI research) and normalize it to markdown into
# /var/lib/kb/staging/<source>/*.md. The existing kb-ingest indexer
# (modules/services/kb-ingest.nix) then vector-indexes that staging area
# hourly, so Hermes' knowledge compounds automatically while he sleeps.
#
# Architecture mirrors kb-ingestion.nix exactly: connectors run as rathi and
# write one markdown file per item into the same staging dir; the root-owned
# indexer picks them up. Dedup is by stable id/url -> deterministic filename:
# a file that already exists is skipped, so re-runs are cheap and idempotent.
#
# No auth, no secrets: every source below is a public, no-auth HTTP endpoint
# (RSS/Atom, the arXiv API, the HN Algolia API). Connectors fail soft - any
# network/parse error logs and exits 0 (no spam, no partial writes).
#
# EDIT ME: the feed/topic lists at the top of this file are the only thing you
# normally touch. Add an RSS url, an arXiv category, or an HN query and rebuild.
let
  user = "rathi";
  group = "users";
  stagingDir = "/var/lib/kb/staging";

  connectorPath = [
    pkgs.jq
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.curl
    pkgs.libxml2 # xmllint, for RSS/Atom + arXiv parsing
  ];

  # --- EDITABLE FEED LISTS ---------------------------------------------------

  # RSS/Atom feeds, aligned to Hari (local-LLM, NixOS, systems/infra, AI).
  # One url per line; blank lines and lines starting with # are ignored.
  rssFeeds = ''
    # local-LLM / inference
    https://simonwillison.net/atom/everything/
    https://huggingface.co/blog/feed.xml
    https://ggml.ai/index.xml
    # NixOS / systems / infra
    https://nixos.org/blog/announcements-rss.xml
    https://lwn.net/headlines/newrss
    # AI research / engineering
    https://jvns.ca/atom.xml
    https://www.anthropic.com/rss.xml
  '';

  # arXiv categories/queries. Each line is an arXiv search_query expression
  # (https://info.arxiv.org/help/api/user-manual.html). Recent submissions
  # in each are pulled, newest first.
  arxivQueries = ''
    cat:cs.AI
    cat:cs.LG
    cat:cs.DC
  '';

  # Hacker News topics (Algolia full-text search, front-page-weighted by date).
  # One query per line. Stories matching any topic are pulled.
  hnQueries = ''
    local llm
    nixos
    llama.cpp
    inference
  '';

  # How many items to keep per feed/query per run (keeps each run light).
  rssMax = "15";
  arxivMax = "20";
  hnMax = "20";
  hnMinPoints = "10"; # ignore HN stories below this score (signal filter)

  # ---------------------------------------------------------------------------

  # Shared markdown front-matter writer helper, inlined per connector as needed.

  # rss connector: each feed url -> staging/feeds/<host>_<hash>.md per item.
  # Handles both RSS (<item>) and Atom (<entry>) via xmllint xpath.
  rssConnector = pkgs.writeShellScript "hermes-feed-rss" ''
    set -uo pipefail
    out="${stagingDir}/feeds"
    mkdir -p "$out"
    total=0
    printf '%s\n' "${rssFeeds}" | grep -vE '^\s*(#|$)' | while read -r url; do
      [ -z "$url" ] && continue
      host=$(printf '%s' "$url" | sed -E 's#^https?://([^/]+).*#\1#')
      xml=$(curl -fsSL --max-time 30 -A 'hermes-feeds/1.0' "$url" 2>/dev/null) || {
        echo "rss: fetch failed: $url"; continue
      }
      # Normalize: strip namespaces so xpath is uniform across RSS/Atom.
      flat=$(printf '%s' "$xml" | sed -E 's/<([a-zA-Z0-9]+):/<\1_/g; s#</([a-zA-Z0-9]+):#</\1_#g')
      # Count items (RSS item or Atom entry).
      count=$(printf '%s' "$flat" \
        | xmllint --recover --xpath 'count(//item | //entry)' - 2>/dev/null) || count=0
      count=$(printf '%s' "$count" | sed 's/[^0-9].*//')
      [ -z "$count" ] && count=0
      i=1
      while [ "$i" -le "$count" ] && [ "$i" -le ${rssMax} ]; do
        node=$(printf '%s' "$flat" \
          | xmllint --recover --xpath "(//item | //entry)[$i]" - 2>/dev/null) || { i=$((i+1)); continue; }
        get() { printf '%s' "$node" | xmllint --recover --xpath "string($1)" - 2>/dev/null; }
        getattr() { printf '%s' "$node" | xmllint --recover --xpath "string($1)" - 2>/dev/null; }
        title=$(get '//title')
        link=$(get '//link')
        [ -z "$link" ] && link=$(getattr '//link/@href') # Atom link is an attr
        desc=$(get '//description')
        [ -z "$desc" ] && desc=$(get '//summary')
        [ -z "$desc" ] && desc=$(get '//content')
        pub=$(get '//pubDate')
        [ -z "$pub" ] && pub=$(get '//updated')
        [ -z "$pub" ] && pub=$(get '//published')
        # Strip HTML tags from the body for cleaner embeddings.
        body=$(printf '%s' "$desc" | sed -E 's/<[^>]+>//g')
        idsrc="''${link:-$title}"
        [ -z "$idsrc" ] && { i=$((i+1)); continue; }
        hash=$(printf '%s' "$idsrc" | md5sum | cut -c1-16)
        f="$out/''${host}_''${hash}.md"
        i=$((i+1))
        [ -f "$f" ] && continue
        {
          printf '# %s\n\n' "''${title:-(untitled)}"
          printf -- '- Source: rss (%s)\n- URL: %s\n- Published: %s\n\n' "$host" "$link" "$pub"
          printf '%s\n' "$body"
        } > "$f"
        total=$((total+1))
      done
      echo "rss: $host -> $count item(s) seen"
    done
    echo "rss: connector done (new files written to $out)"
  '';

  # arxiv connector: each query -> staging/arxiv/<arxiv_id>.md per paper.
  arxivConnector = pkgs.writeShellScript "hermes-feed-arxiv" ''
    set -uo pipefail
    out="${stagingDir}/arxiv"
    mkdir -p "$out"
    api="http://export.arxiv.org/api/query"
    printf '%s\n' "${arxivQueries}" | grep -vE '^\s*(#|$)' | while read -r q; do
      [ -z "$q" ] && continue
      enc=$(printf '%s' "$q" | jq -sRr @uri)
      xml=$(curl -fsSL --max-time 40 \
        "$api?search_query=$enc&start=0&max_results=${arxivMax}&sortBy=submittedDate&sortOrder=descending" \
        2>/dev/null) || { echo "arxiv: fetch failed: $q"; continue; }
      flat=$(printf '%s' "$xml" | sed -E 's/<([a-zA-Z0-9]+):/<\1_/g; s#</([a-zA-Z0-9]+):#</\1_#g')
      count=$(printf '%s' "$flat" | xmllint --recover --xpath 'count(//entry)' - 2>/dev/null) || count=0
      count=$(printf '%s' "$count" | sed 's/[^0-9].*//'); [ -z "$count" ] && count=0
      i=1
      while [ "$i" -le "$count" ]; do
        node=$(printf '%s' "$flat" | xmllint --recover --xpath "(//entry)[$i]" - 2>/dev/null) || { i=$((i+1)); continue; }
        get() { printf '%s' "$node" | xmllint --recover --xpath "string($1)" - 2>/dev/null; }
        idurl=$(get '//id')
        title=$(get '//title' | tr '\n' ' ' | sed -E 's/\s+/ /g')
        summary=$(get '//summary' | sed -E 's/\s+/ /g')
        pub=$(get '//published')
        authors=$(printf '%s' "$node" | xmllint --recover --xpath '//author/name/text()' - 2>/dev/null \
          | tr '\n' ',' | sed -E 's/,+/, /g; s/, $//')
        i=$((i+1))
        # arXiv id like http://arxiv.org/abs/2606.27361v1 -> 2606.27361v1
        aid=$(printf '%s' "$idurl" | sed -E 's#.*/abs/##; s#[^A-Za-z0-9._-]#_#g')
        [ -z "$aid" ] && continue
        f="$out/''${aid}.md"
        [ -f "$f" ] && continue
        {
          printf '# %s\n\n' "''${title:-(untitled)}"
          printf -- '- Source: arxiv\n- URL: %s\n- Published: %s\n- Authors: %s\n\n' "$idurl" "$pub" "$authors"
          printf '%s\n' "$summary"
        } > "$f"
      done
      echo "arxiv: $q -> $count paper(s) seen"
    done
    echo "arxiv: connector done (new files written to $out)"
  '';

  # hackernews connector: each query -> staging/hackernews/<objectID>.md.
  # Uses the Algolia search_by_date endpoint (front-page weighted, no auth).
  hnConnector = pkgs.writeShellScript "hermes-feed-hn" ''
    set -uo pipefail
    out="${stagingDir}/hackernews"
    mkdir -p "$out"
    api="https://hn.algolia.com/api/v1/search"
    printf '%s\n' "${hnQueries}" | grep -vE '^\s*(#|$)' | while read -r q; do
      [ -z "$q" ] && continue
      enc=$(printf '%s' "$q" | jq -sRr @uri)
      json=$(curl -fsSL --max-time 30 \
        "$api?query=$enc&tags=story&hitsPerPage=${hnMax}&numericFilters=points>=${hnMinPoints}" \
        2>/dev/null) || { echo "hn: fetch failed: $q"; continue; }
      n=$(printf '%s' "$json" | jq -r '.hits | length' 2>/dev/null) || n=0
      [ -z "$n" ] && n=0
      printf '%s' "$json" | jq -c '.hits[]?' 2>/dev/null | while read -r hit; do
        oid=$(printf '%s' "$hit" | jq -r '.objectID // empty')
        [ -z "$oid" ] && continue
        f="$out/''${oid}.md"
        [ -f "$f" ] && continue
        title=$(printf '%s' "$hit" | jq -r '.title // "(untitled)"')
        url=$(printf '%s' "$hit" | jq -r '.url // ("https://news.ycombinator.com/item?id=" + .objectID)')
        pts=$(printf '%s' "$hit" | jq -r '.points // 0')
        author=$(printf '%s' "$hit" | jq -r '.author // ""')
        created=$(printf '%s' "$hit" | jq -r '.created_at // ""')
        text=$(printf '%s' "$hit" | jq -r '.story_text // ""' | sed -E 's/<[^>]+>//g')
        {
          printf '# %s\n\n' "$title"
          printf -- '- Source: hackernews (query: %s)\n- URL: %s\n- HN: https://news.ycombinator.com/item?id=%s\n- Points: %s\n- Author: %s\n- Date: %s\n\n' \
            "$q" "$url" "$oid" "$pts" "$author" "$created"
          printf '%s\n' "$text"
        } > "$f"
      done
      echo "hn: $q -> $n story(ies) seen"
    done
    echo "hn: connector done (new files written to $out)"
  '';

  # nitter/X connector: STUBBED. A no-auth X feed needs a working Nitter or
  # RSS-bridge instance, and public ones are rate-limited / frequently down.
  # When Hari stands up an instance, set nitterBase below and drop the guard;
  # the connector then mirrors the rss path (Nitter serves Atom at /<user>/rss).
  nitterBase = ""; # e.g. "https://nitter.example.net"
  nitterAccounts = ''
    # one X handle per line (no @), e.g.
    # ggerganov
    # karpathy
  '';
  nitterConnector = pkgs.writeShellScript "hermes-feed-nitter" ''
    set -uo pipefail
    base="${nitterBase}"
    if [ -z "$base" ]; then
      echo "nitter: no instance configured (nitterBase empty); skipping"
      exit 0
    fi
    out="${stagingDir}/x"
    mkdir -p "$out"
    printf '%s\n' "${nitterAccounts}" | grep -vE '^\s*(#|$)' | while read -r u; do
      [ -z "$u" ] && continue
      xml=$(curl -fsSL --max-time 30 "$base/$u/rss" 2>/dev/null) || { echo "nitter: fetch failed: $u"; continue; }
      flat=$(printf '%s' "$xml" | sed -E 's/<([a-zA-Z0-9]+):/<\1_/g; s#</([a-zA-Z0-9]+):#</\1_#g')
      count=$(printf '%s' "$flat" | xmllint --recover --xpath 'count(//item)' - 2>/dev/null) || count=0
      count=$(printf '%s' "$count" | sed 's/[^0-9].*//'); [ -z "$count" ] && count=0
      i=1
      while [ "$i" -le "$count" ] && [ "$i" -le ${rssMax} ]; do
        node=$(printf '%s' "$flat" | xmllint --recover --xpath "(//item)[$i]" - 2>/dev/null) || { i=$((i+1)); continue; }
        get() { printf '%s' "$node" | xmllint --recover --xpath "string($1)" - 2>/dev/null; }
        link=$(get '//link'); title=$(get '//title')
        body=$(get '//description' | sed -E 's/<[^>]+>//g')
        pub=$(get '//pubDate'); i=$((i+1))
        [ -z "$link" ] && continue
        hash=$(printf '%s' "$link" | md5sum | cut -c1-16)
        f="$out/''${u}_''${hash}.md"
        [ -f "$f" ] && continue
        {
          printf '# @%s\n\n' "$u"
          printf -- '- Source: x (%s)\n- URL: %s\n- Date: %s\n\n' "$u" "$link" "$pub"
          printf '%s\n\n%s\n' "$title" "$body"
        } > "$f"
      done
    done
    echo "nitter: connector done"
  '';

  # A connector service that runs as the user (no creds needed, but matches the
  # kb-ingestion.nix model: connectors are rathi-owned, staging is rathi-owned).
  mkConnector = name: exec: {
    "hermes-feed-${name}" = {
      description = "Hermes feed connector: ${name} -> KB staging";
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
    "hermes-feed-${name}" = {
      description = "Schedule Hermes feed connector: ${name}";
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
  # Staging subdirs, rathi-owned so connectors write and the root indexer reads.
  systemd.tmpfiles.rules = [
    "d ${stagingDir}/feeds 0755 ${user} ${group} -"
    "d ${stagingDir}/arxiv 0755 ${user} ${group} -"
    "d ${stagingDir}/hackernews 0755 ${user} ${group} -"
    "d ${stagingDir}/x 0755 ${user} ${group} -"
  ];

  systemd.services =
    (mkConnector "rss" rssConnector)
    // (mkConnector "arxiv" arxivConnector)
    // (mkConnector "hn" hnConnector)
    // (mkConnector "nitter" nitterConnector);

  # Feeds refresh a few times a day: fresh enough to be useful, light on the
  # public APIs. The kb-ingest timer (kb-ingestion.nix) reindexes hourly and
  # will pick up whatever these connectors have staged.
  systemd.timers =
    (mkTimer "rss" "*-*-* 06,12,18,23:17:00")
    // (mkTimer "arxiv" "*-*-* 07:23:00")
    // (mkTimer "hn" "*-*-* 06,12,18,23:42:00")
    // (mkTimer "nitter" "*-*-* 06,18:33:00");
}
