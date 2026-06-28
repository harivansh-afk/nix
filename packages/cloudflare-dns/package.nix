# cloudflare-dns: terranix wrapper around `tofu` that applies the Cloudflare DNS
# for harivan.sh. Driven by `just dns-plan` / `just dns-apply`
# (`nix run .#cloudflare-dns -- <subcommand>`).
#
# Relocated verbatim from flake/cloudflare.nix into the registry. The terranix
# evaluation lives inside the `let` below so the registry can read `.id` without
# forcing flake inputs; only `.package` pulls in inputs.terranix.
{
  pkgs,
  inputs,
  system,
  ...
}:
let
  terraformConfiguration = inputs.terranix.lib.terranixConfiguration {
    inherit system;
    modules = [ ../../terraform/cloudflare/config.nix ];
  };

  cloudflare-dns = pkgs.writeShellApplication {
    name = "cloudflare-dns";
    runtimeInputs = [
      pkgs.opentofu
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel)"
      work_dir="$repo_root/terraform/cloudflare"
      mkdir -p "$work_dir/state"

      rm -f "$work_dir/config.tf.json"
      cp ${terraformConfiguration} "$work_dir/config.tf.json"
      chmod u+w "$work_dir/config.tf.json"

      sops_token="/run/secrets/cloudflare-api-token"
      if [[ -z "''${CLOUDFLARE_API_TOKEN:-}" && -r "$sops_token" ]]; then
        CLOUDFLARE_API_TOKEN="$(cat "$sops_token")"
        export CLOUDFLARE_API_TOKEN
      fi

      if [[ -z "''${CLOUDFLARE_API_TOKEN:-}" ]]; then
        echo "cloudflare-dns: no Cloudflare API token available." >&2
        echo "  Expected the sops secret at $sops_token (run a switch after adding it)," >&2
        echo "  or set CLOUDFLARE_API_TOKEN for a one-off." >&2
        echo "  See terraform/cloudflare/README.md (SOP: API token)." >&2
        exit 1
      fi

      cd "$work_dir"
      exec tofu "$@"
    '';
    meta.description = "Apply Cloudflare DNS for harivan.sh (terranix wrapper around tofu)";
  };
in
{
  id = "cloudflare-dns";
  package = cloudflare-dns;
  tests.smoke = pkgs.runCommand "cloudflare-dns-smoke" { } ''
    test -x ${cloudflare-dns}/bin/cloudflare-dns || {
      echo "cloudflare-dns: binary missing" >&2
      exit 1
    }
    touch $out
  '';
}
