# secrets/registry.nix
#
# Single source of truth for every sops-nix secret in this flake.
# Consumed by modules/security/sops.nix and home/zsh.nix.
#
# - `user.<name>`        : per-admin-user secrets. Decrypted on every host the
#                          admin's SSH key is a sops recipient for (currently
#                          both macbook and spark). Land at /run/secrets/<name>
#                          and are auto-sourced into interactive zsh.
#                          Defaults: owner = ${username}, mode = "0400".
#
# - `hosts.<host>.<name>`: host-bound secrets. Decrypted only on the named
#                          host. Land at /run/secrets/<name>. Each entry is
#                          passed verbatim into sops.secrets, so it can carry
#                          owner / group / mode / restartUnits / neededForUsers.
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
    "linear.env" = { };
    "graphite.env" = { };
    "mgrep.env" = { };
    "forgejo-token.env" = { };
    "gws.env" = { };
  };

  hosts.spark = {
    "user-password-hash" = {
      neededForUsers = true;
    };

    "wifi.env" = {
      restartUnits = [ "NetworkManager-ensure-profiles.service" ];
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

    "vaultwarden.env" = {
      owner = "vaultwarden";
      group = "vaultwarden";
      mode = "0400";
      restartUnits = [ "vaultwarden.service" ];
    };

    "symphony.env" = {
      owner = username;
      group = "users";
      mode = "0400";
      restartUnits = [ "symphony.service" ];
    };

    "gitea-mirror.env" = {
      owner = "gitea-mirror";
      group = "gitea-mirror";
      mode = "0400";
      restartUnits = [ "gitea-mirror.service" ];
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
