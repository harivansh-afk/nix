{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cua-cli";
  version = "0.2.0";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-sdk-v${finalAttrs.version}/cua-cli-${finalAttrs.version}-linux-arm64.tar.gz";
    sha256 = "6db93d8dc3d7caac40089762bfa51f5f69ee722e608d2b03694b06eef772673e";
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  installPhase = ''
    runHook preInstall
    install -Dm755 cua $out/bin/cua
    wrapProgram $out/bin/cua --set DO_NOT_TRACK 1 --set CUA_TELEMETRY 0
    runHook postInstall
  '';
  meta = {
    description = "Cua CLI for computer and desktop connections";
    homepage = "https://cua.ai/docs/cua-cli";
    license = lib.licenses.mit;
    mainProgram = "cua";
    platforms = [ "aarch64-linux" ];
  };
})
