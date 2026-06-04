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

          if [[ -z "''${CLOUDFLARE_API_TOKEN:-}" ]]; then
            echo "cloudflare-dns: CLOUDFLARE_API_TOKEN is not set." >&2
            echo "  export CLOUDFLARE_API_TOKEN=\"\$(cat /path/to/token)\" and retry." >&2
            exit 1
          fi

          cd "$work_dir"
          exec tofu "$@"
        '';
        meta.description = "Apply Cloudflare DNS for harivan.sh (terranix wrapper around tofu)";
      };
    };
}
