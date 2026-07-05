# secrets/registry.nix
#
# Single source of truth for every sops-nix secret in this flake.
# Consumed by modules/security/sops.nix and modules/users/user-config.nix.
#
# - `user.<name>`        : per-admin-user secrets. Decrypted on every host the
#                          admin's SSH key is a sops recipient for (currently
#                          both macbook and spark). Land at /run/secrets/<name>
#                          and are auto-sourced into interactive zsh unless
#                          `exposeToShell = false`.
#                          Defaults: owner = ${username}, mode = "0400".
#
# - `hosts.<host>.<name>`: host-bound secrets. Decrypted only on the named
#                          host. Land at /run/secrets/<name>. Each entry is
#                          passed verbatim into sops.secrets, so it can carry
#                          owner / group / mode / restartUnits / neededForUsers.
#                          An entry can also override `sopsFile` to point at
#                          a file outside this repo (e.g. a flake input) for
#                          secrets that ship with their consuming service.
#
# Adding a new secret:
#   1. Drop the plaintext or encrypted file into the matching directory:
#        secrets/user/<name>            (user-shell)
#        secrets/hosts/<host>/<name>    (host-bound)
#      .sops.yaml will pick the right recipient set automatically.
#   2. Add a one-line entry here.
#   3. Consume via config.sops.secrets."<name>".path.
{ username }:
{
  user = {
    "antithesis.env" = { };
    "linear.env" = { };
    "graphite.env" = { };
    "mgrep.env" = { };
    "gws.env" = { };
    "mxbai.env" = { };
    "forgejo-ix.env" = {
      format = "dotenv";
    };
    # Raw token (not KEY=value). Consumed verbatim by home/tea.nix and
    # home/git.nix, but must not be sourced by interactive shells.
    "forgejo-token.env" = {
      exposeToShell = false;
      sopsFile = ./hosts/spark/forgejo-token.env;
    };
    # Raw Cloudflare API token. Consumed by the cloudflare-dns runner
    # (flake/cloudflare.nix) from /run/secrets, never sourced into the shell.
    "cloudflare-api-token" = {
      exposeToShell = false;
    };
  };

  hosts.spark = {
    # Raw token (not KEY=value). Consumed verbatim by home/tea.nix
    # (tokenFile) and home/git.nix (cat in credential helper). Kept out
    # of the `user` bucket so macOS does not try to `source` it.
    "forgejo-token.env" = {
      owner = username;
      group = "users";
      mode = "0400";
    };

    "user-password-hash" = {
      neededForUsers = true;
    };

    # gws OAuth token (authorized_user creds incl. refresh token). Read by the
    # gmail/calendar KB connectors via GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE for
    # deterministic, keyring-free auth. Owned by rathi (the connectors run as
    # rathi). Not a KEY=value file, so keep it out of the shell-sourced bucket.
    "gws-credentials.json" = {
      owner = username;
      group = "users";
      mode = "0400";
    };

    "wifi.env" = {
      restartUnits = [ "NetworkManager-ensure-profiles.service" ];
    };

    # SimpleFIN Bridge read-only access URL for the local-only finance KB
    # namespace. KEY=value dotenv with SIMPLEFIN_ACCESS_URL=https://<creds>@... ;
    # the URL carries HTTP Basic credentials inline. Read by the kb-finance
    # SimpleFIN connector (modules/services/kb-finance.nix), which runs as rathi.
    # The connector no-ops cleanly when this secret is absent.
    "simplefin.env" = {
      owner = username;
      group = "users";
      mode = "0400";
    };

    "tailscale-ix-authkey" = {
      owner = "root";
      mode = "0400";
      restartUnits = [ "tailscaled-autoconnect.service" ];
    };

    "cloudflared.json" = {
      mode = "0444";
      restartUnits = [ "cloudflared-tunnel-64bce32c-6613-459c-bb68-262d73e1b78f.service" ];
    };

    "delta.env" = {
      owner = username;
      group = "users";
      mode = "0400";
      restartUnits = [ "delta.service" ];
    };

    # Photon (Spectrum) credentials for the Hermes gateway's iMessage channel:
    # PHOTON_PROJECT_ID / PHOTON_PROJECT_SECRET plus the PHOTON_ALLOWED_USERS
    # allowlist and PHOTON_HOME_CHANNEL (cron/notification DM target).
    # KEY=value dotenv, loaded as the gateway unit's EnvironmentFile
    # (modules/services/hermes.nix). Owned by rathi (the gateway runs as
    # rathi). Fail-closed: only allowlisted numbers (or pairing-approved
    # senders) can talk to the agent.
    "hermes-photon.env" = {
      owner = username;
      group = "users";
      mode = "0400";
      restartUnits = [ "hermes-gateway.service" ];
    };

    # Telegram bot token (+ TELEGRAM_ALLOWED_USERS allowlist). No longer
    # loaded by the gateway (the agent channel moved to Photon iMessage);
    # still read directly at run time by the mini-loop timers
    # (dots/mini-loops/mini_loop.py) for notification delivery, so no
    # restartUnits are needed.
    "hermes-telegram.env" = {
      owner = username;
      group = "users";
      mode = "0400";
    };

    "vaultwarden.env" = {
      owner = "vaultwarden";
      group = "vaultwarden";
      mode = "0400";
      restartUnits = [ "vaultwarden.service" ];
    };

    "forgejo-smtp-password" = {
      owner = "git";
      group = "git";
      mode = "0400";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-mirror.env" = {
      owner = "git";
      group = "git";
      mode = "0400";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-google-oauth.env" = {
      owner = "git";
      group = "git";
      mode = "0400";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-github-oauth.env" = {
      owner = "git";
      group = "git";
      mode = "0400";
      restartUnits = [ "forgejo.service" ];
    };

    "forgejo-runner-token" = {
      owner = "gitea-runner";
      group = "gitea-runner";
      mode = "0400";
      restartUnits = [ "gitea-runner-netty.service" ];
    };

    "barrett-forgejo-runner-token" = {
      owner = "barrett";
      mode = "0400";
    };
  };
}
