{ self, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      neovim = import ../lib/neovim.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        neovim = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.default;
        configDir = ../dots/nvim;
        curated = true;
        extraPackages = [ (pkgs.callPackage ../pkgs/baml-cli { }) ];
      };
      pluginSources = builtins.fromJSON (builtins.readFile ../dots/nvim/pack-sources.json);
      prSource = pkgs.fetchgit { inherit (pluginSources."pr.nvim") url rev hash; };
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
        claude-proxy = inputs.cc-proxy.checks.${pkgs.stdenv.hostPlatform.system}.gateway;
        cc-proxy = inputs.cc-proxy.checks.${pkgs.stdenv.hostPlatform.system}.cli;

        ast-grep = lint "ast-grep" [ pkgs.ast-grep ] "ast-grep scan --error .";
        ast-grep-test = lint "ast-grep-test" [ pkgs.ast-grep ] "ast-grep test --skip-snapshot-tests";
        statix = lint "statix" [ pkgs.statix ] "statix check .";
        deadnix = lint "deadnix" [ pkgs.deadnix ] ''
          deadnix --fail --exclude ./hosts/spark/hardware-configuration.nix -- . # generated file
        '';

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
          patch --batch --fuzz=0 -p1 < ${../hosts/macbook/voiceink/mini-recorder.patch}
          bash -n ${../hosts/macbook/voiceink/build.sh}
          touch $out
        '';
      };
    };
}
