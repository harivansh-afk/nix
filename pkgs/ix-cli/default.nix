{ fetchurl, stdenvNoCC }:
let
  digest = "5f4f14963a8c619ae0793cf7142750a9461d0dcf122878d4c9bbfeac6941c748";
in
stdenvNoCC.mkDerivation {
  pname = "ix-cli";
  version = "2026-08-06";
  src = fetchurl {
    url = "https://ix.dev/cli/linux-x86_64/sha256/${digest}/ix";
    hash = "sha256-X08UljqMYZrgeTz3FCdQqUYdDc8SKHjUybv+rGlBx0g=";
  };
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/ix"
    runHook postInstall
  '';
  meta.mainProgram = "ix";
}
