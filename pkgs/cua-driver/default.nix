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
stdenv.mkDerivation {
  pname = "cua-driver";
  version = "0.23.2";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v0.23.2/cua-driver-rs-0.23.2-linux-arm64-binary.tar.gz";
    hash = "sha256-viJ2iiB3lqS8HeUMUvMvnvaAtehuWMBZ4C7sLKui57s=";
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
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v0.23.2/cua-driver-rs-v0.23.2-skills.tar.gz";
    hash = "sha256-mlvUttmZR6ISiDrvmj4Lcc7jCC2XlnO/RpJHy0RoNVo=";
  };
  meta = {
    description = "Native computer-use driver for Spark";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    mainProgram = "cua-driver";
    platforms = [ "aarch64-linux" ];
  };
}
