{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      terraformConfiguration = inputs.terranix.lib.terranixConfiguration {
        inherit system;
        modules = [ ../terraform/cloudflare/config.nix ];
      };
    in
    {
      packages.cloudflare-dns = pkgs.writeShellApplication {
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
    };
}
