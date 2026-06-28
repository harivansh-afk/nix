{
  lib,
  pkgs,
  ...
}:
# mini-loops.nix - a framework for autonomous "life routines".
#
# A mini-loop runs on a timer and does five things (see dots/mini-loops/mini_loop.py):
#   gather -> ground -> judge -> act -> log
#     gather  run a shell command; its stdout is the gathered items (text).
#     ground  kb-search each seed -> a compact "about Hari" context block.
#     judge   ask the local brain (127.0.0.1:18080, qwen3.6-35b-a3b) which items
#             have an interesting CONSEQUENCE for Hari; returns JSON
#             [{item, relevant, why}].
#     act     for each relevant item: Telegram ping (with the why) and/or a
#             timestamped KB note under staging/loops/<name>/.
#     log     one line to runlog.log (OK/SKIP/FAIL) + a per-run detail JSON.
#
# Loops are declared as the `loops` list below. Each spec generates a oneshot
# systemd service (runs as rathi) + a timer. Everything is loopback-only; no
# ports, no network exposure. This mirrors the kb-research "missions" skeleton
# (modules/services/kb-research.nix) and evolves it: grounding + judging +
# Telegram action + first-class observability.
#
# The flagship loop, x-life-scan, reads the logged-in X home feed. X needs a
# browser session, captured once with `browse-x-login` (see below).
let
  user = "rathi";
  group = "users";

  stateDir = "/var/lib/mini-loops";
  runsDir = "${stateDir}/runs";
  kbLoopsDir = "/var/lib/kb/staging/loops";

  # browser-use state (owned by browser-use.nix); the X session lives here.
  browserUseDir = "/var/lib/browser-use";
  xSessionDir = "${browserUseDir}/x-session";
  xStorageState = "${xSessionDir}/storage_state.json";
  browserUseVenv = "${browserUseDir}/venv";
  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # Plain python for the runner: stdlib only (json, urllib, subprocess).
  runnerPython = pkgs.python3;
  runner = ../../dots/mini-loops/mini_loop.py;

  # The runner shells out to these at runtime; put them on the unit PATH.
  # kb-search (kb-ingest.nix) and x-feed-scan (below) are on the system PATH via
  # environment.systemPackages; systemd units also see /run/current-system/sw.
  loopPath = [
    pkgs.coreutils
    pkgs.bash
    pkgs.jq
    pkgs.curl
    pkgs.gnugrep
    pkgs.gnused
  ];

  # ---------------------------------------------------------------------------
  # Loop specs. EDIT the `seeds` to match what you care about - they are the
  # niches the judge grounds against. `gather` is any shell command whose stdout
  # is the items text. `judge` is the consequence-judging prompt.
  # ---------------------------------------------------------------------------
  loops = [
    {
      name = "x-life-scan";
      # Every 4 hours.
      schedule = "*-*-* 00/4:00:00";
      # Read the logged-in X home feed: ~30 latest posts as text. No-ops (empty
      # stdout -> SKIP) until an X session is captured with `browse-x-login`.
      gather = "x-feed-scan";
      # EDIT THESE: the niches the loop grounds against (kb-search each).
      seeds = [
        "my projects spark nixos hermes agent"
        "local AI inference llama.cpp"
        "personal finance"
        "people I know"
      ];
      judge = ''
        You are scanning Hari's X (Twitter) home feed. Surface only posts with an
        interesting CONSEQUENCE for Hari given the context about him: things that
        affect his projects, tools he uses, people he knows, or his interests.
        Skip generic noise, hot takes, and engagement bait. For each surfaced
        post, the "why" must state the concrete connection to Hari.'';
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
    if [ ! -x ${browserUseVenv}/bin/python ]; then
      echo "x-feed-scan: browser-use venv missing; run browser-use-setup" >&2
      exit 0
    fi
    export BROWSER_USE_CHROMIUM=${chromiumBin}
    export BROWSER_USE_BRAIN_URL=http://127.0.0.1:18080/v1
    export BROWSER_USE_BRAIN_MODEL=qwen3.6-35b-a3b
    export BROWSER_USE_STORAGE_STATE=${xStorageState}
    export HOME="''${HOME:-${browserUseDir}}"
    export BROWSER_USE_SETUP_LOGGING=false
    exec ${browserUseVenv}/bin/python ${../../dots/browser-use/x_feed_scan.py}
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
        ${pkgs.systemd}/bin/systemctl start "mini-loop-$name.service"
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
      path = loopPath;
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
    "d ${kbLoopsDir} 0755 ${user} ${group} -"
    # X session dir (rathi-owned; storage_state.json is written 0600 by the CLI).
    "d ${xSessionDir} 0700 ${user} ${group} -"
  ]
  ++ perLoopKbDirs;

  environment.systemPackages = [
    xFeedScan
    browseXLogin
    loopsCli
  ];

  systemd.services = lib.mkMerge (map mkService loops);
  systemd.timers = lib.mkMerge (map mkTimer loops);
}
