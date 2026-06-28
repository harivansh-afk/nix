{
  config,
  lib,
  pkgs,
  ...
}:
# mini-loops.nix - a framework for autonomous "life routines".
#
# A mini-loop runs on a timer and does five things (see dots/mini-loops/mini_loop.py):
#   gather -> ground -> judge -> act -> log
#     gather  run a shell command; its stdout is the gathered items (text).
#     ground  build an "ACTIVE PROJECTS" block (Hari's recently-pushed GitHub
#             repos + local git repos with a recent commit); falls back to
#             kb-search of the static seeds only if both signals are unreachable.
#     judge   ask the local brain (127.0.0.1:18080, qwen3.6-35b-a3b) which items
#             have a concrete CONSEQUENCE for an active project; returns JSON
#             [{item, relevant, project, headline, why}].
#     act     KB note keeps the full record; Telegram is terse (top 3 items, one
#             project-anchored sentence each) and stays silent if nothing ties to
#             an active project. Notes land under staging/loops/<name>/.
#     log     one line to runlog.log (OK/SKIP/FAIL) + a per-run detail JSON.
#
# Loops are declared as the `loops` list below. Each spec generates a oneshot
# systemd service (runs as rathi) + a timer. Everything is loopback-only; no
# ports, no network exposure (the only outbound calls are the public GitHub API
# for active-projects grounding and each loop's gather source).
#
# The flagship loop, x-life-scan, reads the logged-in X home feed. X needs a
# browser session, captured once with `browse-x-login` (see below).
let
  user = "rathi";
  group = "users";

  stateDir = "/var/lib/mini-loops";
  runsDir = "${stateDir}/runs";
  # Per-loop persistent state (dep-release last-seen tags, finance flagged set).
  loopStateDir = "${stateDir}/state";
  kbLoopsDir = "/var/lib/kb/staging/loops";
  financeDir = "/var/lib/kb/staging/finance";

  # browser-use state (owned by browser-use.nix); the X session lives here.
  browserUseDir = "/var/lib/browser-use";
  xSessionDir = "${browserUseDir}/x-session";
  xStorageState = "${xSessionDir}/storage_state.json";
  browserUseVenv = "${browserUseDir}/venv";
  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # Deterministic X feed scrape uses Playwright (NOT browser-use's agentic loop,
  # which made an LLM call per navigation step and timed out on the local brain).
  # Playwright drives the nix-store chromium directly via executable_path, so we
  # do not need (or use) browser-use's browser bundle here.
  playwrightPython = pkgs.python3.withPackages (ps: [ ps.playwright ]);

  # Plain python for the runner: stdlib only (json, urllib, subprocess).
  runnerPython = pkgs.python3;
  runner = ../../dots/mini-loops/mini_loop.py;

  # The runner shells out to these at runtime; put them on the unit PATH.
  # IMPORTANT: setting systemd `path` REPLACES the default, so units do NOT get
  # /run/current-system/sw/bin. The gather/ground steps call `x-feed-scan` and
  # `kb-search` (system packages), so we add `config.system.path` in mkService
  # below; without it the gather is not found and every run SKIPs.
  loopPath = [
    pkgs.coreutils
    pkgs.bash
    pkgs.jq
    pkgs.curl
    pkgs.gnugrep
    pkgs.gnused
    # The runner shells out to `git` for the local active-projects signal.
    pkgs.git
  ];

  # ---------------------------------------------------------------------------
  # Loop specs. The runner grounds each loop against Hari's ACTIVE PROJECTS (his
  # recently-pushed GitHub repos + local git repos with a recent commit), not the
  # static seeds - the judge surfaces an item only if it has a concrete
  # consequence for one of those active projects. `seeds` is now only the kb-search
  # FALLBACK grounding (used if both project signals are unreachable). `gather` is
  # any shell command whose stdout is the items text; `judge` is the prompt.
  # ---------------------------------------------------------------------------
  loops = [
    {
      name = "x-life-scan";
      # Every 4 hours.
      schedule = "*-*-* 00/4:00:00";
      # Read the logged-in X home feed: ~30 latest posts as text. No-ops (empty
      # stdout -> SKIP) until an X session is captured with `browse-x-login`.
      gather = "x-feed-scan";
      # Fallback grounding only (the runner prefers the active-projects signal).
      seeds = [
        "my projects spark nixos hermes agent"
        "local AI inference llama.cpp"
        "personal finance"
        "people I know"
      ];
      judge = ''
        You are scanning Hari's X (Twitter) home feed. Surface only posts with a
        concrete CONSEQUENCE for one of Hari's active projects: something that
        changes how he should build, a tool/dependency he uses, or a result he can
        act on. The connection must genuinely make sense - no stretchy links. Skip
        generic noise, hot takes, and engagement bait.'';
      # Gate requires a concrete tie to a currently-active project.
      gate = "active-project";
      telegram = true;
      kb = true;
    }
    {
      name = "hn-life-scan";
      # Every 6 hours.
      schedule = "*-*-* 00/6:00:00";
      # Hacker News front page (~40 stories) via the Algolia API; no key/browser.
      gather = "hn-feed-scan";
      seeds = [
        "my projects spark nixos hermes agent"
        "local AI inference llama.cpp"
        "developer tools self-hosting"
      ];
      judge = ''
        You are scanning the Hacker News front page. Surface only stories with a
        concrete CONSEQUENCE for one of Hari's active projects: a tool, library,
        technique, or result he could directly use or that changes a decision in
        one of those projects. The connection must genuinely make sense - no
        stretchy links. Skip generic tech news, hype, and drama.'';
      gate = "active-project";
      telegram = true;
      kb = true;
    }
    {
      name = "dep-release-watch";
      # Daily, early morning.
      schedule = "*-*-* 07:00:00";
      # Check the curated dependency watchlist for NEW releases (one line each).
      # Edit the watchlist in dots/mini-loops/dep_release_scan.py (WATCHLIST).
      gather = "dep-release-scan";
      seeds = [
        "my projects spark nixos hermes agent"
        "local AI inference llama.cpp"
        "dependencies libraries I use"
      ];
      judge = ''
        You are scanning NEW releases of dependencies Hari's projects rely on.
        Surface a release ONLY if it is genuinely MAJOR for one of his active
        projects: a breaking change, a major new capability, a significant
        performance win, or a security fix that affects him. Treat patch bumps,
        docs/CI changes, and routine incremental releases as noise.'';
      gate = "active-project";
      telegram = true;
      kb = true;
    }
    {
      name = "finance-anomaly-watch";
      # Daily, morning.
      schedule = "*-*-* 08:00:00";
      # Deterministic anomaly candidates from the locally-ingested finance notes.
      gather = "finance-anomaly-scan";
      # Finance does not use the project signal; seeds are an unused fallback.
      seeds = [ "personal finance spending subscriptions" ];
      judge = ''
        You are reviewing CANDIDATE spending anomalies in Hari's own accounts
        (already computed deterministically): new recurring subscriptions, price
        hikes on existing subscriptions, unusually large charges, and duplicate
        charges. Surface only ones that are real and worth his attention; ignore
        normal recurring spend and trivial amounts.'';
      # Money loop: the gate keys on a real, novel anomaly, NOT a project tie.
      gate = "anomaly";
      telegram = true;
      kb = true;
    }
  ];

  # ---------------------------------------------------------------------------
  # Per-loop spec JSON file (read by the runner via $MINI_LOOP_SPEC).
  # ---------------------------------------------------------------------------
  specFile =
    loop:
    pkgs.writeText "mini-loop-${loop.name}.json" (
      builtins.toJSON {
        inherit (loop)
          name
          gather
          seeds
          judge
          gate
          telegram
          kb
          ;
      }
    );

  # ---------------------------------------------------------------------------
  # x-feed-scan: gather the logged-in X home feed as text (storage_state).
  # Separate deterministic entrypoint so the loop's gather is one command.
  # ---------------------------------------------------------------------------
  xFeedScan = pkgs.writeShellScriptBin "x-feed-scan" ''
    set -uo pipefail
    if [ ! -s ${xStorageState} ]; then
      echo "x-feed-scan: no X session (run browse-x-login)" >&2
      exit 0
    fi
    export BROWSER_USE_CHROMIUM=${chromiumBin}
    export BROWSER_USE_STORAGE_STATE=${xStorageState}
    # Playwright uses chromium via executable_path; skip its own browser download.
    export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export HOME="''${HOME:-${browserUseDir}}"
    exec ${playwrightPython}/bin/python ${../../dots/browser-use/x_feed_scan.py}
  '';

  # ---------------------------------------------------------------------------
  # hn-feed-scan: gather the Hacker News front page as text (Algolia API).
  # Stdlib-only python; no key, no browser. One story per line.
  # ---------------------------------------------------------------------------
  hnFeedScan = pkgs.writeShellScriptBin "hn-feed-scan" ''
    exec ${runnerPython}/bin/python ${../../dots/mini-loops/hn_feed_scan.py}
  '';

  # ---------------------------------------------------------------------------
  # dep-release-scan: gather NEW releases of the curated dependency watchlist.
  # Stdlib-only python; GitHub public API, no key. State (last-seen tags) lives
  # under ${loopStateDir}. Edit the watchlist in dep_release_scan.py (WATCHLIST).
  # ---------------------------------------------------------------------------
  depReleaseScan = pkgs.writeShellScriptBin "dep-release-scan" ''
    export MINI_LOOPS_DIR="''${MINI_LOOPS_DIR:-${stateDir}}"
    exec ${runnerPython}/bin/python ${../../dots/mini-loops/dep_release_scan.py}
  '';

  # ---------------------------------------------------------------------------
  # finance-anomaly-scan: gather deterministic spending anomaly candidates from
  # the locally-ingested finance notes. Stdlib-only python; NO network. State
  # (already-flagged anomalies) lives under ${loopStateDir}.
  # ---------------------------------------------------------------------------
  financeAnomalyScan = pkgs.writeShellScriptBin "finance-anomaly-scan" ''
    export MINI_LOOPS_DIR="''${MINI_LOOPS_DIR:-${stateDir}}"
    export FINANCE_KB_DIR="''${FINANCE_KB_DIR:-${financeDir}}"
    exec ${runnerPython}/bin/python ${../../dots/mini-loops/finance_anomaly_scan.py}
  '';

  # ---------------------------------------------------------------------------
  # browse-x-login: capture a logged-in X session as storage_state.json.
  #   Headed (default): opens a VISIBLE Chromium - run once over `ssh -X spark`,
  #     log in by hand; the session is saved automatically.
  #   Headless import: if X_AUTH_TOKEN and X_CT0 are set, writes the cookie pair
  #     directly (no display needed).
  # ---------------------------------------------------------------------------
  browseXLogin = pkgs.writeShellScriptBin "browse-x-login" ''
    set -euo pipefail
    if [ ! -x ${browserUseVenv}/bin/python ]; then
      echo "browse-x-login: browser-use venv missing; run browser-use-setup first" >&2
      exit 1
    fi
    mkdir -p ${xSessionDir}
    export BROWSER_USE_CHROMIUM=${chromiumBin}
    export BROWSER_USE_STORAGE_STATE=${xStorageState}
    export HOME="''${HOME:-${browserUseDir}}"
    export BROWSER_USE_SETUP_LOGGING=false
    ${browserUseVenv}/bin/python ${../../dots/browser-use/x_login.py}
    chmod 0600 ${xStorageState} 2>/dev/null || true
  '';

  # ---------------------------------------------------------------------------
  # loops: observe + trigger the mini-loops.
  # ---------------------------------------------------------------------------
  loopNames = map (l: l.name) loops;
  loopsCli = pkgs.writeShellScriptBin "loops" ''
    set -uo pipefail
    runlog="${stateDir}/runlog.log"
    cmd="''${1:-status}"
    case "$cmd" in
      status)
        echo "== recent runs (${stateDir}/runlog.log) =="
        ${pkgs.coreutils}/bin/tail -n 20 "$runlog" 2>/dev/null || echo "(no runs yet)"
        echo
        echo "== timers =="
        ${pkgs.systemd}/bin/systemctl list-timers --all 'mini-loop-*' --no-pager 2>/dev/null \
          || echo "(no timers)"
        ;;
      run)
        name="''${2:-}"
        if [ -z "$name" ]; then echo "usage: loops run <name>" >&2; exit 2; fi
        # System unit: starting it manually needs root (the timer fires it
        # automatically without sudo). Use the sudo wrapper.
        /run/wrappers/bin/sudo ${pkgs.systemd}/bin/systemctl start "mini-loop-$name.service"
        echo "triggered mini-loop-$name.service"
        ;;
      log)
        name="''${2:-}"
        if [ -n "$name" ]; then
          ${pkgs.coreutils}/bin/tail -n 50 "$runlog" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -- " $name " || true
        else
          ${pkgs.coreutils}/bin/tail -n 50 "$runlog" 2>/dev/null || echo "(no runs yet)"
        fi
        ;;
      *)
        echo "usage: loops {status|run <name>|log [name]}" >&2
        echo "loops: ${lib.concatStringsSep " " loopNames}" >&2
        exit 2
        ;;
    esac
  '';

  # ---------------------------------------------------------------------------
  # systemd service + timer per loop.
  # ---------------------------------------------------------------------------
  mkService = loop: {
    "mini-loop-${loop.name}" = {
      description = "Mini-loop: ${loop.name}";
      after = [
        "network-online.target"
        "browser-use-setup.service"
      ];
      wants = [ "network-online.target" ];
      path = loopPath ++ [ config.system.path ];
      environment = {
        MINI_LOOP_SPEC = "${specFile loop}";
        MINI_LOOPS_DIR = stateDir;
        MINI_LOOPS_KB_DIR = kbLoopsDir;
      };
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = "${runnerPython}/bin/python ${runner} ${loop.name}";
        # Generous window: gather may drive a headless browser + brain calls.
        TimeoutStartSec = "1200";
      };
    };
  };

  mkTimer = loop: {
    "mini-loop-${loop.name}" = {
      description = "Schedule mini-loop: ${loop.name}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = loop.schedule;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };

  perLoopKbDirs = map (l: "d ${kbLoopsDir}/${l.name} 0755 ${user} ${group} -") loops;
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 ${user} ${group} -"
    "d ${runsDir} 0755 ${user} ${group} -"
    "d ${loopStateDir} 0755 ${user} ${group} -"
    "d ${kbLoopsDir} 0755 ${user} ${group} -"
    # X session dir (rathi-owned; storage_state.json is written 0600 by the CLI).
    "d ${xSessionDir} 0700 ${user} ${group} -"
  ]
  ++ perLoopKbDirs;

  environment.systemPackages = [
    xFeedScan
    hnFeedScan
    depReleaseScan
    financeAnomalyScan
    browseXLogin
    loopsCli
  ];

  systemd.services = lib.mkMerge (map mkService loops);
  systemd.timers = lib.mkMerge (map mkTimer loops);
}
