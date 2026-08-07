{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "herdr-ix-space";
  version = "0.1.0";
  src = ./.;
  installPhase = ''
    runHook preInstall
    install -Dm755 ix-space "$out/bin/ix-space"
    mkdir -p "$out/share/herdr-ix-space"
    substitute herdr-plugin.toml "$out/share/herdr-ix-space/herdr-plugin.toml" \
      --replace-fail @out@ "$out"
    runHook postInstall
  '';
  meta.mainProgram = "ix-space";
}
