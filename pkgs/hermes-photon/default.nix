{ pkgs, hermes }:
let
  upstream = hermes.packages.${pkgs.stdenv.hostPlatform.system}.default;
  plugins = pkgs.applyPatches {
    name = "hermes-plugins-photon-replies";
    src = hermes + "/plugins";
    patches = [ ./threaded-replies.patch ];
  };
  testPython = pkgs.python312.withPackages (ps: [
    ps.pytest
    ps.pytest-asyncio
    ps.pytest-timeout
  ]);
  tests =
    pkgs.runCommand "hermes-photon-reply-tests"
      {
        nativeBuildInputs = [
          pkgs.nodejs
          pkgs.git
          testPython
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cp -r ${hermes} source
        chmod -R u+w source
        cd source
        rm -r plugins
        cp -r ${plugins} plugins
        chmod -R u+w plugins
        cp ${./test_reply_boundary.py} tests/plugins/platforms/photon/test_reply_boundary.py
        python3 -m venv --without-pip .venv
        printf '%s\n' \
          '${testPython}/${pkgs.python312.sitePackages}' \
          '${upstream.hermesVenv}/${pkgs.python312.sitePackages}' \
          > .venv/${pkgs.python312.sitePackages}/nix-runtime.pth
        git init -q
        git add '*.py'
        bash scripts/run_tests.sh -j 2 tests/plugins/platforms/photon/test_reply_boundary.py \
          tests/plugins/platforms/photon/test_inbound.py \
          tests/plugins/platforms/photon/test_reactions.py \
          tests/plugins/platforms/photon/test_mention_gating.py \
          tests/plugins/platforms/photon/test_rich_links.py
        node --check plugins/platforms/photon/sidecar/index.mjs
        node --check plugins/platforms/photon/sidecar/normalize-content.mjs
        touch $out
      '';
in
{
  inherit plugins;
  package = upstream.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      rm $out/share/hermes-agent/plugins
      ln -s ${plugins} $out/share/hermes-agent/plugins
    '';
    passthru = (old.passthru or { }) // {
      tests = (old.passthru.tests or { }) // {
        photon-replies = tests;
      };
    };
  });
}
