# Lint gates as flake checks: one entrypoint for local and CI.
{ self, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      neovim = import ../lib/neovim.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        configDir = ../dots/nvim;
        curated = true;
        extraPackages = [ (pkgs.callPackage ../pkgs/baml-cli { }) ];
      };
      pluginSources = builtins.fromJSON (builtins.readFile ../dots/nvim/pack-sources.json);
      prSource = pkgs.fetchgit { inherit (pluginSources."pr.nvim") url rev hash; };
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
          pkgs.git
        ] "bash ${prSource}/scripts/test.sh";

        neovim = lint "neovim" [ pkgs.bash pkgs.coreutils pkgs.git neovim ] "bash scripts/nvim-smoke.sh";
        stylua = lint "stylua" [ pkgs.stylua ] "stylua --check dots/nvim";
        logitech = lint "logitech" [ pkgs.python3 ] "python3 hosts/macbook/logitech/test_apply.py";
        mixbridge = inputs.mixbridge-web.checks.${pkgs.stdenv.hostPlatform.system}.streaming-api;
        voiceink-patches = pkgs.runCommand "voiceink-patches" { nativeBuildInputs = [ pkgs.patch ]; } ''
          cp -R ${inputs.voiceink-src} source
          chmod -R u+w source
          cd source
          patch --batch --fuzz=0 -p1 < ${../hosts/macbook/voiceink/streaming-provider.patch}
          patch --batch --fuzz=0 -p1 < ${../hosts/macbook/voiceink/mini-recorder.patch}
          bash -n ${../hosts/macbook/voiceink/build.sh}
          touch $out
        '';
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
        hermes-runtime =
          pkgs.runCommand "hermes-runtime"
            {
              nativeBuildInputs = [
                hermes.package
              ]
              ++ hermes.extraPackages;
              relaySource = builtins.head hermes.extraPlugins;
              profileConfigs = pkgs.writeText "hermes-profile-check.json" (
                builtins.toJSON {
                  default = hermes.configFile;
                  imessage = hermes.hermesHomeFiles."profiles/imessage/config.yaml";
                  desktop = pkgs.writeText "desktop.json" hermes.hermesHomeFiles."profiles/desktop/config.yaml";
                  roommates = pkgs.writeText "roommates.json" hermes.hermesHomeFiles."profiles/roommates/config.yaml";
                }
              );
            }
            ''
              export HOME=$TMPDIR/home HERMES_HOME=$TMPDIR/home/.hermes
              mkdir -p "$HERMES_HOME"
              hermes --version
              export PYTHONPATH=${hermes.package}/share/hermes-agent
              uv run --offline --no-project --python ${hermes.package.hermesVenv}/bin/python3 \
                ${../scripts/test-hermes-relay.py}
              touch $out
            '';
      };
    };
}
