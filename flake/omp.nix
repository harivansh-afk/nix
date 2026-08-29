# omp (oh-my-pi) from the upstream release binaries; a source build needs
# network in the sandbox. Bump: `version` + the per-asset hashes
# (`gh release view v<version> --repo can1357/oh-my-pi --json assets`), then
# run scripts/omp/claude-hooks-smoke.sh.
_: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      version = "16.3.4";
      assets = {
        aarch64-linux = {
          name = "omp-linux-arm64";
          hash = "sha256-6c62RokhOv4b3LwX1N3/BoRLGreUA17VEsdwSLwEFq4=";
        };
        x86_64-linux = {
          name = "omp-linux-x64";
          hash = "sha256-axXfGYpTezJN1+fJOAH/EehAGSmCfaMEdr9jAheCBug=";
        };
        aarch64-darwin = {
          name = "omp-darwin-arm64";
          hash = "sha256-soPwaXaytyPIwh5L7nCcTFMpIlaoSDcfch7m+gVcr9Y=";
        };
        x86_64-darwin = {
          name = "omp-darwin-x64";
          hash = "sha256-W2ZQkfu4QyxvkY1LShb4GoTuetjw/gfFcJKyP0UIEZM=";
        };
      };
      asset = assets.${system} or null;
    in
    lib.optionalAttrs (asset != null) {
      packages.omp = pkgs.stdenvNoCC.mkDerivation {
        pname = "omp";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${asset.name}";
          inherit (asset) hash;
        };

        dontUnpack = true;
        dontStrip = true;

        # The binary links only glibc; patching the interpreter makes the
        # package run on hosts without nix-ld.
        nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.autoPatchelfHook
        ];

        installPhase = ''
          runHook preInstall
          install -Dm755 $src $out/bin/omp
          runHook postInstall
        '';

        meta = {
          description = "Oh My Pi coding agent (upstream release binary)";
          homepage = "https://github.com/can1357/oh-my-pi";
          license = lib.licenses.mit;
          mainProgram = "omp";
          platforms = builtins.attrNames assets;
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      };
    };
}
