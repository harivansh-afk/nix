{
  config,
  inputs,
  pkgs,
  ...
}:
# hermes-briefing.nix - a daily "morning briefing" delivered to Telegram.
#
# What this does
# --------------
# Every morning a systemd timer (kb-ingestion.nix style) invokes Hermes in
# headless one-shot mode (`hermes -z "<prompt>"`) as user `rathi`. The agent
# gathers Hari's day - today's calendar, important/starred unread email (both
# via `gws`), local weather (via the `web` toolset), and a couple of fresh
# items from his KB feeds (via `kb-search`) - composes one short, scannable
# brief, and SENDS it to his Telegram DM with the built-in `send_message`
# tool. No interactive session, no human at a terminal.
#
# Why one-shot instead of the native cron tool
# --------------------------------------------
# Hermes ships a `cronjob` toolset that writes jobs to ~/.hermes/cron/jobs.json
# and runs them from the in-process scheduler inside `hermes gateway`. We do NOT
# use it: it is mutable runtime state (the gateway rewrites it), it can only be
# seeded by talking to the agent, and it is exactly the kind of ~/.hermes state
# this repo keeps declarative. A systemd timer is the cleaner, reproducible,
# rebuild-tracked mechanism - and it matches kb-ingestion.nix.
#
# How headless delivery to Telegram works (verified against the package source,
# tools/send_message_tool.py + gateway/config.py in hermes-agent 0.14.0)
# ----------------------------------------------------------------------
# `hermes -z` runs a single agent turn with the user's configured "cli" toolset
# (messaging + terminal + web + kb via terminal), auto-approving tool calls
# (HERMES_YOLO_MODE). When the agent calls `send_message`, the tool:
#   1. Loads the gateway config. `_apply_env_overrides()` reads TELEGRAM_BOT_TOKEN
#      from the process env and enables the Telegram platform with that token.
#      We feed the SAME sops secret the gateway uses (hermes-telegram.env) as
#      this unit's EnvironmentFile, so the token is present without any plaintext
#      in the repo or nix store.
#   2. With no explicit chat_id, it resolves the platform "home channel"
#      (TELEGRAM_HOME_CHANNEL). Crucially, send_message's standalone path
#      (_send_to_platform -> _send_telegram) talks to the Telegram Bot API
#      directly with the token + chat_id, so NO running gateway adapter is
#      needed - this is the documented out-of-process / cron delivery path.
#
# The home channel (Hari's DM chat_id)
# ------------------------------------
# For a 1:1 Telegram DM the user's Telegram user ID *is* the chat ID. Hari's
# hermes-telegram.env already carries TELEGRAM_ALLOWED_USERS (his allowlisted
# account). So when TELEGRAM_HOME_CHANNEL is not set explicitly, the
# briefing script derives it from the first TELEGRAM_ALLOWED_USERS entry and
# exports it for the run. This gives true end-to-end delivery with zero
# plaintext secrets and no manual wiring. To override (e.g. deliver to a group
# or topic), add a TELEGRAM_HOME_CHANNEL=<id> line to the hermes-telegram.env
# sops secret and it wins.
let
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };

  user = "rathi";
  home = "/home/${user}";
  hermesHome = "${home}/.hermes";

  # When the briefing should land. 07:30 local, persistent so a missed run
  # (host asleep) fires on the next boot. RandomizedDelaySec keeps it human.
  briefingTime = "*-*-* 07:30:00";

  # The brief itself. Tight, high-signal, Hari-tuned: he hates filler, wants one
  # line per item, and truly urgent-only outside working hours. The agent has
  # the cli toolset (terminal -> gws + kb-search, web -> weather, messaging ->
  # send_message). gws read access (gmail/calendar) needs no approval; this run
  # is non-interactive and auto-approves anyway.
  #
  # TOOLS.md and the gws/kb permission model are already injected into the
  # agent's context (symlinked persona). The prompt stays deliberately short and
  # leans on that context rather than re-teaching the tools.
  briefingPrompt = ''
    Compose Hari's MORNING BRIEFING for today and DELIVER it to him on Telegram with the send_message tool (no chat_id - use the Telegram home channel).

    Gather, in this order, then write ONE message:
    1. CALENDAR: today's events via `gws calendar events list` (primary, timeMin=now, timeMax=end of today, singleEvents, orderBy=startTime). One line each: time - title (location if any). Flag back-to-backs / conflicts.
    2. EMAIL: important or starred UNREAD via gws gmail (e.g. `gws gmail users messages list --params '{"userId":"me","maxResults":15,"q":"is:unread (is:starred OR is:important)"}'`), then fetch metadata headers. One line each: sender - subject. Skip marketing/newsletters/automated noise.
    3. WEATHER: today's local forecast (high/low + conditions) for Hari's city (use what you know about where he is from memory; if unknown, fetch via web). One short line.
    4. KB: run `kb-search` for 1-2 genuinely fresh, relevant items from his feeds (e.g. `kb-search "latest"` or a topic he tracks). At most 2 lines. Skip if nothing new/useful.

    FORMAT (strict, Hari hates fluff):
    - Start with a single header line: "Morning brief - <weekday>, <Mon DD>".
    - Then short sections only for what has content: Today / Email / Weather / Notes. Omit any empty section entirely.
    - One line per item, max. No preamble, no sign-off, no emojis, no em dashes.
    - If a source is empty, say nothing about it (do not write "no events").
    - If literally everything is empty, send a one-liner: "Morning brief - <date>: clear calendar, nothing urgent."
    - Keep the whole message scannable in ~10 seconds.

    Privacy: never include content from the KB denylist. This is a personal brief for Hari only; send it to him on Telegram and nowhere else.
  '';

  # Derive TELEGRAM_HOME_CHANNEL from the first allowlisted Telegram user (a 1:1
  # DM's user ID == its chat ID) unless one is set explicitly, then run the
  # one-shot. Never writes a secret to disk - only exports for this process.
  briefingScript = pkgs.writeShellScript "hermes-briefing" ''
    set -uo pipefail

    # The agent shells out to `gws` and `kb-search` (the terminal tool) by bare
    # name; both live on the system profile. Put it on PATH so the one-shot run
    # can reach them, the same wrappers the kb connectors use.
    export PATH="/run/current-system/sw/bin:$PATH"

    # Telegram home channel: explicit override wins; otherwise use the first
    # entry of the allowlist (the DM user id == chat id for a 1:1 chat).
    if [ -z "''${TELEGRAM_HOME_CHANNEL:-}" ] && [ -n "''${TELEGRAM_ALLOWED_USERS:-}" ]; then
      export TELEGRAM_HOME_CHANNEL="''${TELEGRAM_ALLOWED_USERS%%,*}"
    fi

    if [ -z "''${TELEGRAM_BOT_TOKEN:-}" ]; then
      echo "hermes-briefing: TELEGRAM_BOT_TOKEN missing; cannot deliver. Skipping." >&2
      exit 0
    fi
    if [ -z "''${TELEGRAM_HOME_CHANNEL:-}" ]; then
      echo "hermes-briefing: no TELEGRAM_HOME_CHANNEL and no TELEGRAM_ALLOWED_USERS to derive one; set TELEGRAM_HOME_CHANNEL in the hermes-telegram.env secret. Skipping." >&2
      exit 0
    fi

    # One-shot: generate the brief and let the agent deliver via send_message.
    # Output (the agent's final text) goes to the journal for observability.
    exec ${hermes}/bin/hermes -z ${pkgs.lib.escapeShellArg briefingPrompt}
  '';
in
{
  systemd.services.hermes-briefing = {
    description = "Hermes morning briefing -> Telegram (headless one-shot)";
    after = [
      "network-online.target"
      "hermes-gateway.service"
      "llama-cpp.service"
    ];
    wants = [
      "network-online.target"
      "llama-cpp.service"
    ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      # Pin the local brain for the one-shot run, mirroring the gateway. The
      # one-shot reads the model name from config.yaml model.default; these are
      # the same belt-and-suspenders hints hermes.nix sets on the gateway.
      HERMES_INFERENCE_PROVIDER = "custom";
      CUSTOM_BASE_URL = "http://127.0.0.1:18080/v1";
    };

    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = home;

      # Reuse the gateway's Telegram secret: provides TELEGRAM_BOT_TOKEN (and
      # TELEGRAM_ALLOWED_USERS, from which we derive the home channel). No
      # plaintext token anywhere in the repo or nix store.
      EnvironmentFile = config.sops.secrets."hermes-telegram.env".path;

      ExecStart = briefingScript;

      # The brief touches gws creds, kb-search, and ~/.hermes state under /home.
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [ home ];
      PrivateTmp = true;
      NoNewPrivileges = true;

      # The local 120b brain can take a while for a multi-tool turn; give it
      # room but cap it so a wedged run cannot hang forever.
      TimeoutStartSec = "900";

      StandardOutput = "journal";
      StandardError = "journal";
    };

    path = [
      hermes
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.curl
    ];
  };

  systemd.timers.hermes-briefing = {
    description = "Schedule the Hermes morning briefing";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = briefingTime;
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };
}
