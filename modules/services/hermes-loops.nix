{
  inputs,
  lib,
  pkgs,
  ...
}:
# hermes-loops.nix - Hari's proactive loops, centered on the hermes agent.
#
# Four loops, four hermes cron jobs, one delivery channel (photon/iMessage),
# every run a resumable session in the agent's own history. The split is:
# data acquisition stays deterministic, judgment goes to a model, delivery is
# always the agent.
#
#   x-life-scan          every 4h   x-feed-scan (Playwright, saved X session)
#   hn-life-scan         every 6h   hn-feed-scan (Algolia API)
#   dep-release-watch    daily      dep-release-scan (GitHub releases + state)
#   finance-anomaly-watch daily     finance-anomaly-scan + LOCAL qwen judge
#
# The three feed loops pair a gather script with the feed-triage skill: the
# scanner's stdout is injected into the cron prompt, the agent (cloud model)
# grounds, judges, files the KB note, and replies with the ping or [SILENT].
#
# Finance is different because the raw data is local-only: the gateway masks
# /var/lib/kb/staging/finance via InaccessiblePaths, and hermes' cron scheduler
# runs IN the gateway process, so no cron job - whatever model it is pinned to -
# can ever read it. Instead `finance-anomaly-judge` (a systemd timer OUTSIDE
# that sandbox, allowed to reach loopback only) runs the deterministic scanner
# and has the local qwen brain (127.0.0.1:18080) write a judged briefing into
# staging/loops/, which the gateway CAN read. The finance-anomaly-watch cron
# job then relays that verdict: hermes sees only the local model's result,
# never the raw transactions, and delivers it over photon like everything else.
# The judge unit's IPAddressDeny=any means the one process that combines raw
# finance data with an LLM is structurally unable to reach the internet.
#
# Job installation is declarative: a nix-generated manifest is converged into
# ~/.hermes/cron/jobs.json by dots/hermes/cron/reconcile.py, which runs under
# hermes' own python env and drives hermes' cron.jobs module directly (locking,
# schedule parsing and next_run_at stay first-party; the gateway re-reads
# jobs.json every scheduler tick). The reconciler owns only the names it
# installed (~/.hermes/cron/.nix-managed.json), so jobs created via /cron in
# chat survive rebuilds untouched.
let
  user = "rathi";
  group = "users";
  home = "/home/${user}";
  hermesHome = "${home}/.hermes";

  # Same base package as hermes.nix: the reconciler runs under this venv so the
  # cron.jobs module it imports is byte-identical to the gateway's.
  hermesBase = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };
  inherit (hermesBase) hermesVenv;

  # Loop state (release dedupe and finance verdicts).
  # Migrated once from the old mini-loops path by the C tmpfiles rule below so
  # dedupe state survives and nothing is re-surfaced; drop that rule (and
  # /var/lib/mini-loops) after the first rebuild has run everywhere.
  stateDir = "/var/lib/loops";
  loopStateDir = "${stateDir}/state";
  oldStateDir = "/var/lib/mini-loops";

  kbLoopsDir = "/var/lib/kb/staging/loops";
  financeDir = "/var/lib/kb/staging/finance";
  verdictDir = "${kbLoopsDir}/finance-anomaly-watch";

  # Local brain (modules/services/inference.nix).
  brainUrl = "http://127.0.0.1:18080/v1/chat/completions";
  brainModel = "qwen3.6-35b-a3b";

  # browser-use state (owned by browser-use.nix); the X session lives here.
  browserUseDir = "/var/lib/browser-use";
  xSessionDir = "${browserUseDir}/x-session";
  xStorageState = "${xSessionDir}/storage_state.json";
  browserUseVenv = "${browserUseDir}/venv";
  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # Deterministic X feed scrape uses Playwright directly (NOT browser-use's
  # agentic loop, which made an LLM call per navigation step and timed out).
  playwrightPython = pkgs.python3.withPackages (ps: [ ps.playwright ]);
  scanPython = pkgs.python3;

  # ---------------------------------------------------------------------------
  # Scanners: reproducible data acquisition, exported as system packages so the
  # cron gather shims (and Hari) can run them by name.
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

  hnFeedScan = pkgs.writeShellScriptBin "hn-feed-scan" ''
    exec ${scanPython}/bin/python ${../../dots/loops/hn_feed_scan.py}
  '';

  depReleaseScan = pkgs.writeShellScriptBin "dep-release-scan" ''
    export LOOPS_DIR="''${LOOPS_DIR:-${stateDir}}"
    exec ${scanPython}/bin/python ${../../dots/loops/dep_release_scan.py}
  '';

  # Local-only and sensitive: reads the staged finance notes, no network.
  financeAnomalyScan = pkgs.writeShellScriptBin "finance-anomaly-scan" ''
    export LOOPS_DIR="''${LOOPS_DIR:-${stateDir}}"
    export FINANCE_KB_DIR="''${FINANCE_KB_DIR:-${financeDir}}"
    exec ${scanPython}/bin/python ${../../dots/loops/finance_anomaly_scan.py}
  '';

  # browse-x-login: capture a logged-in X session as storage_state.json.
  #   Headed (default): opens a VISIBLE Chromium - run once over `ssh -X spark`,
  #     log in by hand; the session is saved automatically.
  #   Headless import: if X_AUTH_TOKEN and X_CT0 are set, writes the cookie pair
  #     directly (no display needed).
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
  # Feed loops: schedule + scanner + judgment framing for the feed-triage skill.
  # ---------------------------------------------------------------------------
  feedLoops = {
    x-life-scan = {
      schedule = "0 */4 * * *";
      gather = "x-feed-scan";
      prompt = "Triage the posts below from Hari's X home feed against what he is working on right now.";
    };
    hn-life-scan = {
      schedule = "0 */6 * * *";
      gather = "hn-feed-scan";
      prompt = "Triage the Hacker News front-page stories below against what Hari is working on right now.";
    };
    dep-release-watch = {
      schedule = "0 7 * * *";
      gather = "dep-release-scan";
      prompt = "Triage the new dependency releases below. Only a genuinely major release for an active project earns a ping.";
    };
  };

  # Gather shim per feed job: runs the scanner, injects its stdout into the
  # cron prompt; empty stdout or a timeout prints hermes' wake gate
  # {"wakeAgent": false} so a quiet feed skips the LLM run entirely.
  gatherScript =
    name: loop:
    pkgs.writeText "${name}.py" ''
      import json
      import subprocess
      import sys

      GATHER = "/run/current-system/sw/bin/${loop.gather}"

      try:
          proc = subprocess.run(
              [GATHER], capture_output=True, text=True, timeout=270
          )
      except subprocess.TimeoutExpired:
          sys.stderr.write("${loop.gather}: timed out\n")
          print(json.dumps({"wakeAgent": False}))
          raise SystemExit(0)

      if proc.stderr.strip():
          sys.stderr.write(proc.stderr)

      items = (proc.stdout or "").strip()
      if not items:
          print(json.dumps({"wakeAgent": False}))
          raise SystemExit(0)

      print(items)
    '';

  # Relay shim for the finance job: injects verdict notes the judge wrote since
  # the last relay. The marker seeds to "newest existing" on first run so
  # history (including old mini-loop notes in the same directory) is never
  # replayed. The marker advances when a verdict is handed to the agent, so a
  # failed agent run does not re-ping - the verdict is still in the KB.
  financeRelayScript = pkgs.writeText "finance-anomaly-watch.py" ''
    import json
    from pathlib import Path

    VERDICT_DIR = Path("${verdictDir}")
    MARKER = VERDICT_DIR / ".relayed"

    notes = sorted(p.name for p in VERDICT_DIR.glob("*.md"))
    if not notes:
        print(json.dumps({"wakeAgent": False}))
        raise SystemExit(0)

    if not MARKER.exists():
        MARKER.write_text(notes[-1])
        print(json.dumps({"wakeAgent": False}))
        raise SystemExit(0)

    last = MARKER.read_text().strip()
    fresh = [name for name in notes if name > last]
    if not fresh:
        print(json.dumps({"wakeAgent": False}))
        raise SystemExit(0)

    for name in fresh:
        print((VERDICT_DIR / name).read_text())
    MARKER.write_text(fresh[-1])
  '';

  # ---------------------------------------------------------------------------
  # The cron manifest the reconciler converges into ~/.hermes/cron/jobs.json.
  # ---------------------------------------------------------------------------
  cronManifest = pkgs.writeText "hermes-cron-manifest.json" (
    builtins.toJSON {
      jobs =
        lib.mapAttrsToList (name: loop: {
          inherit name;
          inherit (loop) schedule prompt;
          skills = [ "feed-triage" ];
          script = "${name}.py";
          deliver = "photon";
        }) feedLoops
        ++ [
          {
            name = "finance-anomaly-watch";
            # After finance-anomaly-judge (08:00 + up to 5min jitter) is done.
            schedule = "45 8 * * *";
            prompt = "Relay the finance loop verdict below to Hari.";
            skills = [ "finance-relay" ];
            script = "finance-anomaly-watch.py";
            deliver = "photon";
          }
        ];
      scripts =
        lib.mapAttrs' (name: loop: lib.nameValuePair "${name}.py" "${gatherScript name loop}") feedLoops
        // {
          "finance-anomaly-watch.py" = "${financeRelayScript}";
        };
    }
  );
in
{
  # Converge hermes cron jobs with the manifest on every activation/boot.
  systemd.services.hermes-cron-jobs = {
    description = "Reconcile hermes cron jobs with the flake manifest";
    wantedBy = [ "multi-user.target" ];
    after = [ "hermes-gateway.service" ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      HERMES_CRON_MANIFEST = "${cronManifest}";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = user;
      WorkingDirectory = home;
      ExecStart = "${hermesVenv}/bin/python ${../../dots/hermes/cron/reconcile.py}";
    };
  };

  # Stage one of the finance loop: deterministic scan + local qwen briefing.
  # The ONLY process that combines raw finance data with a model, and it can
  # only reach loopback.
  systemd.services.finance-anomaly-judge = {
    description = "Judge finance anomaly candidates with the local brain";
    after = [ "llama-cpp.service" ];

    environment = {
      FINANCE_SCAN_CMD = "${financeAnomalyScan}/bin/finance-anomaly-scan";
      BRAIN_URL = brainUrl;
      BRAIN_MODEL = brainModel;
      VERDICT_DIR = verdictDir;
    };

    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      ExecStart = "${scanPython}/bin/python ${../../dots/loops/finance_judge.py}";
      TimeoutStartSec = "600";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [
        stateDir
        kbLoopsDir
      ];
      # Raw finance data never leaves the machine: loopback only, no internet.
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
    };
  };

  systemd.timers.finance-anomaly-judge = {
    description = "Schedule the finance anomaly judge";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };

  systemd.tmpfiles.rules = [
    # One-time state migration from the mini-loops era (C = copy only if the
    # target does not exist yet). Remove together with /var/lib/mini-loops
    # once every host has rebuilt.
    "C ${stateDir} 0755 ${user} ${group} - ${oldStateDir}"
    "d ${stateDir} 0755 ${user} ${group} -"
    "d ${loopStateDir} 0755 ${user} ${group} -"
    "d ${kbLoopsDir} 0755 ${user} ${group} -"
    # X session dir (rathi-owned; storage_state.json is written 0600 by the CLI).
    "d ${xSessionDir} 0700 ${user} ${group} -"
  ]
  ++ lib.mapAttrsToList (name: _: "d ${kbLoopsDir}/${name} 0755 ${user} ${group} -") feedLoops
  ++ [ "d ${verdictDir} 0755 ${user} ${group} -" ];

  environment.systemPackages = [
    xFeedScan
    hnFeedScan
    depReleaseScan
    financeAnomalyScan
    browseXLogin
  ];
}
