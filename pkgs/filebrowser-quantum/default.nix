{ pkgs }:
let
  version = "1.5.6-stable";
  release =
    {
      aarch64-linux = {
        platform = "linux-arm64";
        sha256 = "0ad12910ffe51bc3ad06096af9559147f1126d074ed5c8a1afdf81ae5d7ebf24";
      };
      x86_64-linux = {
        platform = "linux-amd64";
        sha256 = "febf1ded3368eac1f13481f413db272c57678b70f09e74f5513d5e25e0bfb0e5";
      };
      aarch64-darwin = {
        platform = "darwin-arm64";
        sha256 = "dff575a3898e845ae2c0ccc6b254cb4819e36eeed5c2ccf16087c570b7fbd081";
      };
      x86_64-darwin = {
        platform = "darwin-amd64";
        sha256 = "236dd7445e518f8fcfb94ccb45e3e7fa81a284db0994a2105d953c1df2e76448";
      };
    }
    .${pkgs.stdenv.hostPlatform.system};
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "filebrowser-quantum";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/gtsteffaniak/filebrowser/releases/download/v${version}/${release.platform}-filebrowser";
    inherit (release) sha256;
  };
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/filebrowser-quantum
    runHook postInstall
  '';
  meta = {
    description = "FileBrowser Quantum filesystem sharing and editing";
    homepage = "https://github.com/gtsteffaniak/filebrowser";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "filebrowser-quantum";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
