{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  targets = {
    aarch64-linux = {
      target = "linux-aarch64";
      hash = "sha256-lD60TIEjM/1FDaEgl1Ia/TM5Q26G+MKsYYuQXEyezmg=";
    };
    aarch64-darwin = {
      target = "macos-aarch64";
      hash = "sha256-HYaxyfukf6cHpvDpdrIFELB8HCbQ7QELlBSyosXmvu8=";
    };
  };
  target = targets.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zmx";
  version = "0.8.1";

  # Upstream's flake fetches its zig dependencies at build time, which the
  # sandbox refuses, so this installs the release binary instead.
  src = fetchurl {
    url = "https://github.com/neurosnap/zmx/releases/download/v${finalAttrs.version}/zmx-${finalAttrs.version}-${target.target}.tar.gz";
    inherit (target) hash;
  };
  sourceRoot = ".";
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 zmx "$out/bin/zmx"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR"
    "$out/bin/zmx" help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Session persistence for terminal processes";
    homepage = "https://zmx.sh";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "zmx";
    platforms = builtins.attrNames targets;
  };
})
