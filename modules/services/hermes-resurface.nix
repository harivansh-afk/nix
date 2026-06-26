{
  config,
  inputs,
  pkgs,
  ...
}:
# hermes-resurface.nix - "On this day" serendipitous resurfacing agent.
#
# What this does
# --------------
# Once a day a systemd timer wakes Hermes in oneshot mode (`hermes -z`), hands
# it a fixed "resurfacing" brief, and lets the agent do the work end to end:
#   1. Pull a slice of Hari's own knowledge base (kb-search over his indexed
#      notes / docs / repos / recent mail+calendar) using a rotating set of
#      open, reflective probe queries, so a different corner surfaces daily.
#   2. Pick the single most genuinely-interesting item - an old note, a dropped
#      idea, a thing worth picking back up - not the most recent or the most
#      obvious.
#   3. Text it to Hari on Telegram in his voice (short, lowercase ok, no fluff)
#      with one line on WHY it might matter today: a "remember this?" nudge.
#
# Why a oneshot, not the built-in cron toolset
# --------------------------------------------
# Hermes ships a `cronjob` toolset + scheduler, but that toolset is deliberately
# OFF in the lean CLI surface (modules/services/hermes.nix `cliToolsetsOff`).
# Rather than widen the model's always-on tool surface for one daily job, we
# drive it from the outside with a plain systemd timer - the same decoupled
# "timer pulls, agent acts" pattern as kb-ingestion.nix. The agent only uses
# tools it ALREADY has in the lean CLI set: `terminal` (to run kb-search) and
# `messaging` (send_message -> Telegram). No new toolset is enabled.
#
# How delivery works
# ------------------
# `hermes -z` runs with HERMES_YOLO_MODE auto-set (no approval prompts) and the
# user's configured CLI toolset. We give it the SAME environment the gateway
# has: HERMES_HOME = ~/.hermes (shared state, incl. the gateway-maintained
# ~/.hermes/channel_directory.json that send_message reads to resolve the
# Telegram target) and the hermes-telegram.env EnvironmentFile (TELEGRAM_BOT_TOKEN).
# With that token in the process env, gateway.config.load_gateway_config()
# enables the Telegram platform (verified in the package source: load_gateway_
# config reads TELEGRAM_BOT_TOKEN and sets platforms[TELEGRAM].enabled/token),
# so send_message(action='send', target='telegram:<chat>') delivers even though
# the long-lived gateway owns the bot's polling loop. The prompt tells the agent
# to discover the target via send_message(action='list') first, so we hardcode
# no chat id here.
#
# Runtime / safety
# ----------------
# - Runs as rathi (same user as the gateway) so it shares ~/.hermes and can read
#   the rathi-owned hermes-telegram.env secret. Type=oneshot.
# - Read-only by design: it searches the KB and sends ONE telegram message. It
#   never writes KB state. (It MAY append a note to its own memory if it judges
#   it useful - that is the agent's normal, sanctioned memory surface, scoped to
#   ~/.hermes and harmless.)
# - The DENYLIST in dots/hermes/TOOLS.md still applies: kb-search never indexes
#   the denylisted paths, and the persona forbids surfacing sensitive material.
# - Tolerant: if the brain or KB is not ready, the oneshot just produces nothing
#   useful and exits 0; no Restart means a bad day is skipped, not retried in a
#   loop. Persistent timer catches a missed run after downtime.
let
  # Same hermes build as the gateway: the `messaging` extra bakes in
  # python-telegram-bot so send_message can actually reach Telegram from a
  # read-only nix store (no runtime pip-install). Kept in lockstep with
  # modules/services/hermes.nix on purpose.
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };

  user = "rathi";
  home = "/home/${user}";
  hermesHome = "${home}/.hermes";

  provider = "custom";
  baseUrl = "http://127.0.0.1:18080/v1";

  # The resurfacing brief, passed as the oneshot prompt. It is intentionally
  # prescriptive about the ONE output: a single short Telegram message. The
  # probe-rotation guidance lives in the prompt so the model varies which corner
  # of the KB it digs into each day.
  brief = ''
    You are running as a scheduled background job (no human is watching this turn). Task: surface ONE serendipitous item from Hari's own knowledge base and text it to him on Telegram. Do it silently and end with the message sent - do not narrate your steps.

    Steps:
    1. Run a few kb-search queries (via the terminal tool) to dig up an OLD or half-forgotten item worth resurfacing - an old note, a dropped idea, a project he paused, a saved thing he never came back to. Vary your probes so different corners surface on different days; lean on open, reflective queries (e.g. "idea I wanted to revisit", "project I paused", "note about <a topic from his world: nix, local AI, agents, self-hosting, systems, automation, privacy>", "something I said I'd do"). Prefer the interesting and the forgotten over the recent and the obvious.
    2. Pick exactly ONE item. If kb-search returns nothing usable, stop and send nothing (just end the turn).
    3. Send it to Hari on Telegram. First call send_message with action=list to find his Telegram target, then send_message action=send to that target. The message:
       - is short: 1-3 lines, lowercase is fine, his voice (no corporate tone, no emoji, no em dashes).
       - leads with the resurfaced thing ("remember this? ...") and adds ONE line on why it might be worth a second look today.
       - never includes anything from the DENYLIST or anything that looks sensitive (credentials, finance, identity, legal). When in doubt, skip it and pick something else.
    4. Send at most ONE message. Then end the turn.
  '';

  resurfaceScript = pkgs.writeShellScript "hermes-resurface" ''
    set -uo pipefail
    # Tolerate a not-yet-ready brain/KB: a failed oneshot must not spam or loop.
    ${hermes}/bin/hermes -z ${pkgs.lib.escapeShellArg brief} || {
      echo "hermes resurface: oneshot failed (brain/KB not ready?); skipping today"
      exit 0
    }
  '';
in
{
  systemd.services.hermes-resurface = {
    description = "Hermes 'on this day' resurfacing agent (one daily Telegram nudge)";
    after = [
      "network-online.target"
      "llama-cpp.service"
      "hermes-gateway.service"
    ];
    wants = [
      "network-online.target"
      "llama-cpp.service"
    ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      # Same provider/base_url hints as the gateway so the oneshot resolves the
      # local brain (the model name comes from ~/.hermes/config.yaml, shared).
      HERMES_INFERENCE_PROVIDER = provider;
      CUSTOM_BASE_URL = baseUrl;
    };

    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = home;

      # TELEGRAM_BOT_TOKEN (+ allowlist) - same secret the gateway uses. With the
      # token in the process env, send_message can deliver to Telegram.
      EnvironmentFile = config.sops.secrets."hermes-telegram.env".path;

      ExecStart = resurfaceScript;

      # One shot per day; give the model room to search + reason on the local
      # 120B brain without being killed mid-turn, but cap it so a wedged run
      # cannot hang forever.
      TimeoutStartSec = "900";
      OOMScoreAdjust = 500;

      # Hardening, mirroring the gateway. ProtectHome must stay off: HERMES_HOME
      # and the shared persona/channel state live under /home/rathi.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [ home ];
      PrivateTmp = true;
    };

    path = [
      hermes
      pkgs.bash
      pkgs.coreutils
    ];
  };

  systemd.timers.hermes-resurface = {
    description = "Schedule the daily Hermes resurfacing nudge";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Late morning local time: he is likely awake and it is past the heartbeat
      # email/calendar noise, so the nudge lands as a standalone moment. This job
      # simply never fires at night, keeping quiet hours quiet.
      OnCalendar = "*-*-* 10:30:00";
      Persistent = true;
      # Smear the start so it does not collide with the hourly kb-ingest /
      # connector wakeups and the brain is not contended at a hard tick.
      RandomizedDelaySec = "20min";
    };
  };
}
