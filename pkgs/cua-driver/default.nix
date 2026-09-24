{
  lib,
  stdenv,
  fetchurl,
  fetchzip,
  autoPatchelfHook,
  makeWrapper,
  sway,
  wtype,
  grim,
  libx11,
  libxi,
  libxkbcommon,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cua-driver";
  version = "0.28.3-nightly.20260924.35955966930";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/nightly-cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-${finalAttrs.version}-linux-arm64-binary.tar.gz";
    hash = "sha256-uXJ5OD3RM/lqsU0MKMVM3Yhdr1R9QJpqi6lxzzhyUdQ=";
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    libx11
    libxi
    libxkbcommon
    stdenv.cc.cc.lib
  ];
  installPhase = ''
    runHook preInstall
    install -Dm755 cua-driver $out/bin/cua-driver
    wrapProgram $out/bin/cua-driver --prefix PATH : ${
      lib.makeBinPath [
        sway
        wtype
        grim
      ]
    }
    runHook postInstall
  '';
  passthru.skills = fetchzip {
    url = "https://github.com/trycua/cua/releases/download/nightly-cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-v${finalAttrs.version}-skills.tar.gz";
    hash = "sha256-JdxrbgFVRHmLHJzrxQVByvz0kS0a8R6VEOlropHIRxM=";
  };
  meta = {
    description = "Native computer-use driver for Spark";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    mainProgram = "cua-driver";
    platforms = [ "aarch64-linux" ];
  };
})
