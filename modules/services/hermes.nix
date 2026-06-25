{
  config,
  inputs,
  pkgs,
  ...
}:
# hermes.nix - Nous Research Hermes Agent gateway as an always-on service.
#
# What this does
# --------------
# Runs `hermes gateway` (the standalone messaging-platform gateway, the proper
# entry point for a long-lived service) as a systemd service for user `rathi`,
# pointed at the local llama.cpp brain from inference.nix
# (OpenAI-compatible, 127.0.0.1:18080, model alias "nemotron-3-super-120b").
#
# State lives in HERMES_HOME = /home/rathi/.hermes (Hermes' default is ~/.hermes;
# we set it explicitly so the systemd unit and interactive `hermes` invocations
# share the same state). Persona files are symlinked from the LIVE repo checkout
# so editing them in dots/hermes takes effect without a rebuild.
#
# Package
# -------
# Discovered via `nix flake show github:NousResearch/hermes-agent/v2026.5.16`:
#   packages.aarch64-linux.default = "hermes-agent-0.14.0", exposing bin/hermes.
# The orchestrator wires a direct flake input named `hermes-agent`; we reference
# packages.<system>.default below. (The flake also ships its own
# nixosModules.default `services.hermes-agent`, but that targets a dedicated
# system user under /var/lib/hermes and declaratively manages config.yaml +
# `.managed` mode. We intentionally do NOT use it: we want per-user `rathi`
# state under /home/rathi/.hermes, live-editable persona symlinks, and a
# mutable config.yaml the interactive CLI can still edit.)
#
# Pointing Hermes at the local brain
# ----------------------------------
# Hermes' "custom" provider is any OpenAI-compatible endpoint (aliases: ollama,
# vllm, llamacpp, ...). It reads three things for routing:
#   - model.provider  (config.yaml)  -> "custom"
#   - model.base_url  (config.yaml)  -> http://127.0.0.1:18080/v1
#   - model.default   (config.yaml)  -> "nemotron-3-super-120b"  (model name)
# Env vars HERMES_INFERENCE_PROVIDER and CUSTOM_BASE_URL also influence
# provider/base_url resolution, but the *model name* the gateway uses comes from
# config.yaml `model.default` (runtime_provider.py reads model_cfg["default"]);
# there is no robust env override for it. So config.yaml must hold the model name.
#
# ~/.hermes/config.yaml is MUTABLE runtime state (it carries `_config_version`
# and is rewritten by the app, e.g. when you run `/model`). We therefore do NOT
# manage/overwrite it declaratively. Instead an idempotent ExecStartPre patches
# only a small set of pinned keys - model.provider/base_url/default, the CLI
# toolset (platform_toolsets.cli), and built-in-only memory (reverting any
# external provider) - and only when they differ, using Hermes' own
# `hermes config set` / `hermes tools` / `hermes memory off` (which preserve
# `_config_version` and every other key via atomic partial writes).
# Tradeoff: a manual `/model` switch to a different
# provider/base_url is reverted on the next service (re)start, which is the
# intended behaviour for an always-on gateway pinned to the local brain. (To
# point the gateway at a different model name, change the `model` binding in
# this module - a manual `hermes config set model.default` is re-pinned on the
# next service restart.) We deliberately
# leave HERMES_MANAGED unset and create no `.managed` marker, because that
# marker makes `hermes config set` (and interactive edits) refuse to run.
#
# Runtime caveats
# ---------------
# - Requires the inference service: ordered After/Wants llama-cpp.service so the
#   brain is (being) brought up first. The gateway tolerates a not-yet-ready
#   endpoint and Restart=on-failure covers a cold start race.
# - Loopback only. The gateway itself talks out to messaging platforms; it does
#   not bind a public listener here. No 0.0.0.0 bind.
# - Messaging-platform secrets: the Telegram bot token (and an optional
#   TELEGRAM_ALLOWED_USERS allowlist) are provided via the sops secret
#   `hermes-telegram.env`, loaded as the unit's EnvironmentFile below. The
#   gateway reads them from its process environment, so no plaintext token
#   lives in the repo, the nix store, or ~/.hermes/.env. Other platforms
#   (Discord, Slack, ...) can be added the same way. The local brain needs no
#   API key. The gateway is fail-closed: with no allowlist configured it denies
#   all users until one is added to the secret or approved via pairing.
let
  # Build the hermes venv with the `messaging` extra so python-telegram-bot is
  # baked into the env. Upstream marks the telegram/discord/slack backends as
  # lazy-install (excluded from the default `all` extra), but runtime
  # pip-install can't work against a read-only nix store - without this the
  # gateway logs "Telegram: python-telegram-bot not installed / No adapter
  # available for telegram" and the bot never connects. The extra also pulls
  # discord/slack (unused for now, but cheap and harmless).
  hermes = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    extraDependencyGroups = [ "messaging" ];
  };

  user = "rathi";
  home = "/home/${user}";
  hermesHome = "${home}/.hermes";

  # Live repo checkout (NOT a /nix/store path) so persona edits apply without a
  # rebuild. Matches the pi.nix convention of hardcoding /home/rathi paths.
  repoHermesDir = "${home}/Documents/Git/nix/dots/hermes";

  provider = "custom";
  baseUrl = "http://127.0.0.1:18080/v1";
  model = "nemotron-3-super-120b";

  # The curated lean CLI toolset. Stored by `hermes tools` as the allow-list
  # `platform_toolsets.cli`. Everything not listed here is disabled for the CLI
  # platform, trimming the model's tool surface from ~30 tools to this set.
  cliToolsets = [
    "clarify"
    "code_execution"
    "file"
    "memory"
    "messaging"
    "session_search"
    "skills"
    "terminal"
    "web"
  ];
  # Toolsets we explicitly turn off (the complement of cliToolsets among the
  # built-in toolsets). Listed so the pin is self-documenting and idempotent.
  cliToolsetsOff = [
    "browser"
    "vision"
    "image_gen"
    "tts"
    "todo"
    "delegation"
    "cronjob"
    "moa"
    "homeassistant"
    "rl"
  ];

  # Memory is deliberately BUILT-IN ONLY (no external provider). We optimize the
  # local model for low confusion: it has exactly three non-overlapping recall
  # surfaces - the always-on built-in `memory` (injected identity/prefs, never
  # queried), `kb-search` (the user's own data), and `session_search` (past
  # conversations). A second agent-authored store (e.g. the bundled
  # `holographic`/`fact_store` provider) overlaps `memory` and `kb-search` and
  # confused the model, so the ExecStartPre reverts any drift back to built-in.

  # Idempotently pin model.* / memory (built-in only) / the CLI toolset in the mutable
  # config.yaml, leaving _config_version and every other key intact. Hermes has
  # no `config get`, so we read current values with yq (read-only) and only
  # write when something actually differs - so a steady-state restart is a
  # no-op. yq prints "null" for a missing key, which never matches a wanted
  # value. Tradeoff: a manual `hermes tools`/`hermes config set` change to any
  # pinned key is reverted on the next gateway restart, which is intended for an
  # always-on gateway pinned to a known-good configuration.
  pinModelConfig = pkgs.writeShellScript "hermes-pin-config" ''
    set -euo pipefail
    cfg="${hermesHome}/config.yaml"

    set_if_diff() {
      key="$1"; want="$2"
      have="null"
      if [ -f "$cfg" ]; then
        have="$(${pkgs.yq-go}/bin/yq -r ".$key // \"null\"" "$cfg" 2>/dev/null || echo null)"
      fi
      if [ "$have" != "$want" ]; then
        ${hermes}/bin/hermes config set "$key" "$want"
      fi
    }

    set_if_diff model.provider "${provider}"
    set_if_diff model.base_url "${baseUrl}"
    set_if_diff model.default "${model}"

    # Built-in memory only: revert any external memory provider drift. Uses the
    # blessed `hermes memory off` (not a raw empty config write) and only acts
    # when a provider is actually set, so steady-state restarts stay no-ops.
    have_mem="$(${pkgs.yq-go}/bin/yq -r '.memory.provider // ""' "$cfg" 2>/dev/null || echo "")"
    if [ -n "$have_mem" ]; then
      ${hermes}/bin/hermes memory off || true
    fi

    # Pin the CLI toolset. Compare the current allow-list to the wanted one
    # (order-insensitive); only reconcile via `hermes tools` when they differ.
    want_tools="${toString cliToolsets}"
    want_sorted="$(printf '%s\n' $want_tools | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    have_sorted="$(${pkgs.yq-go}/bin/yq -r '.platform_toolsets.cli // [] | sort | join(" ")' "$cfg" 2>/dev/null || echo "")"
    if [ "$have_sorted" != "$want_sorted" ]; then
      ${hermes}/bin/hermes tools disable ${toString cliToolsetsOff} || true
      ${hermes}/bin/hermes tools enable $want_tools || true
    fi
  '';
in
{
  systemd.services.hermes-gateway = {
    description = "Nous Research Hermes Agent gateway (local brain)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "llama-cpp.service"
    ];
    wants = [
      "network-online.target"
      "llama-cpp.service"
    ];

    environment = {
      HOME = home;
      HERMES_HOME = hermesHome;
      # Belt-and-suspenders provider/base_url hints (config.yaml stays the
      # source of truth for the model name). Deliberately NOT setting
      # HERMES_MANAGED, so `hermes config set` and interactive edits keep working.
      HERMES_INFERENCE_PROVIDER = provider;
      CUSTOM_BASE_URL = baseUrl;
    };

    serviceConfig = {
      Type = "simple";
      User = user;
      WorkingDirectory = home;

      # Pin the local-brain provider/model before the gateway starts. Runs as
      # the same user, with the service environment (so HERMES_HOME is honoured)
      # but without HERMES_MANAGED, so config set is permitted.
      ExecStartPre = pinModelConfig;
      ExecStart = "${hermes}/bin/hermes gateway";

      # Messaging-platform secrets (sops-encrypted, decrypted to /run/secrets).
      # Holds TELEGRAM_BOT_TOKEN (+ optional TELEGRAM_ALLOWED_USERS). The gateway
      # reads these from its process environment, so an EnvironmentFile is enough
      # - no plaintext token in the repo or nix store. The gateway is fail-closed:
      # with no allowlist it denies all users until one is added or paired.
      EnvironmentFile = config.sops.secrets."hermes-telegram.env".path;

      Restart = "on-failure";
      RestartSec = 5;
      # First start may resolve/seed HERMES_HOME state; keep a generous window
      # like the other GPU/python services here.
      TimeoutStartSec = "300";
      OOMScoreAdjust = 500;

      # Hardening, modelled on the existing services and the upstream hermes
      # NixOS module. ProtectHome must stay off: HERMES_HOME and the live
      # persona symlinks live under /home/rathi.
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
      pkgs.git
    ];
  };

  # Ensure HERMES_HOME exists and symlink the live, repo-managed persona files
  # into it (pi.nix pattern). `L+` overwrites an existing plain file/symlink, so
  # a previously app-seeded SOUL.md is replaced by the repo's. We only link the
  # static, version-controlled persona inputs:
  #   SOUL.md, AGENTS.md, TOOLS.md, HEARTBEAT.md
  # and deliberately leave USER.md, MEMORY.md and ~/.hermes/memories/ alone -
  # those are agent-curated runtime state.
  systemd.user.tmpfiles.users.${user}.rules = [
    "d ${hermesHome} 0700 - - -"
    "L+ ${hermesHome}/SOUL.md - - - - ${repoHermesDir}/SOUL.md"
    "L+ ${hermesHome}/AGENTS.md - - - - ${repoHermesDir}/AGENTS.md"
    "L+ ${hermesHome}/TOOLS.md - - - - ${repoHermesDir}/TOOLS.md"
    "L+ ${hermesHome}/HEARTBEAT.md - - - - ${repoHermesDir}/HEARTBEAT.md"
  ];
}
