{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cua-spaces";
  version = "0.3.0";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-spaces-v${finalAttrs.version}/cua-spaces-${finalAttrs.version}-darwin-universal.dmg";
    sha256 = "7c9a740378d915e736b45ab60e2262f163e3e0535b373dfd0885372736b5e329";
  };
  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "Cua Spaces.app" $out/Applications/
    runHook postInstall
  '';
  meta = {
    description = "Cua Spaces desktop viewer";
    homepage = "https://spaces.cua.ai";
    license = {
      shortName = "FSL-1.1-MIT";
      fullName = "Functional Source License, Version 1.1, MIT Future License";
      url = "https://github.com/trycua/cua/blob/cua-spaces-v0.3.0/apps/cua-spaces-macos/LICENSE";
      free = false;
      redistributable = true;
    };
    platforms = lib.platforms.darwin;
  };
})
