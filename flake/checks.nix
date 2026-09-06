# Lint gates as flake checks: one entrypoint for local and CI.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      hermes = self.nixosConfigurations.spark.config.services.hermes-agent;
      lint =
        name: tools: script:
        pkgs.runCommand "lint-${name}" { nativeBuildInputs = tools; } ''
          cd ${self}
          ${script}
          touch $out
        '';
    in
    {
      checks = {
        # House nix rules (ast-grep/nix/rules); the test check keeps each
        # rule matching its fixtures.
        ast-grep = lint "ast-grep" [ pkgs.ast-grep ] "ast-grep scan --error .";
        ast-grep-test = lint "ast-grep-test" [ pkgs.ast-grep ] "ast-grep test --skip-snapshot-tests";
        statix = lint "statix" [ pkgs.statix ] "statix check .";
        deadnix = lint "deadnix" [ pkgs.deadnix ] ''
          deadnix --fail --exclude ./hosts/spark/hardware-configuration.nix -- . # generated file
        '';
        # dots/zsh excluded: shfmt cannot parse zsh.
        shfmt = lint "shfmt" [
          pkgs.shfmt
          pkgs.findutils
        ] "shfmt -i 2 -d scripts pkgs hosts $(find dots -mindepth 1 -maxdepth 1 ! -name zsh)";
        pr = lint "pr" [
          pkgs.bash
          pkgs.coreutils
          pkgs.neovim
        ] "bash scripts/pr-smoke.sh";

        stylua = lint "stylua" [ pkgs.stylua ] "stylua --check dots/nvim";
        logitech = lint "logitech" [ pkgs.python3 ] "python3 hosts/macbook/logitech/test_apply.py";
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
        hermes-runtime =
          pkgs.runCommand "hermes-runtime"
            {
              nativeBuildInputs = [
                hermes.package
                pkgs.nodejs
              ]
              ++ hermes.extraPackages;
              inherit (hermes.environment) HERMES_CUA_DRIVER_CMD PHOTON_SIDECAR_DIR;
            }
            ''
              export HOME=$TMPDIR/home HERMES_HOME=$TMPDIR/home/.hermes
              export CUA_DRIVER_RS_TELEMETRY_ENABLED=0
              export ANONYMIZED_TELEMETRY=false
              mkdir -p "$HERMES_HOME"
              hermes --version
              hermes computer-use status
              browser-use --version
              agent-browser --version
              cd "$PHOTON_SIDECAR_DIR"
              node --input-type=module -e '
                await import("spectrum-ts");
                await import("./send-format.mjs");
                await import("./stream-staleness.mjs");
              '
              touch $out
            '';
      };
    };
}
