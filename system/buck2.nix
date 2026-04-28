{
  lib,
  stdenv,
  fetchurl,
  zstd,
}:
let
  version = "2026-04-15";
  sources = {
    aarch64-darwin = {
      url = "https://github.com/facebook/buck2/releases/download/${version}/buck2-aarch64-apple-darwin.zst";
      hash = "sha256-zBZ2gEPRxyaBYmnRfYfhYDqswqfiXvxYDHrUI92Z1UQ=";
    };
    aarch64-linux = {
      url = "https://github.com/facebook/buck2/releases/download/${version}/buck2-aarch64-unknown-linux-musl.zst";
      hash = "sha256-siq98ge7jjPQ97XRY1c45GeecyFLim7n+0l+49+YpQg=";
    };
    x86_64-darwin = {
      url = "https://github.com/facebook/buck2/releases/download/${version}/buck2-x86_64-apple-darwin.zst";
      hash = "sha256-G/xarAld9dXanZl7Ivcuoer3YsytmFXWED44u2U4q8g=";
    };
    x86_64-linux = {
      url = "https://github.com/facebook/buck2/releases/download/${version}/buck2-x86_64-unknown-linux-musl.zst";
      hash = "sha256-1vwtufObj0W+zQjWeLD8Hc47TnF28kcbrTe0R9wAX/0=";
    };
  };
  platform = stdenv.hostPlatform.system;
  source = sources.${platform} or (throw "buck2: unsupported platform ${platform}");
in
stdenv.mkDerivation {
  pname = "buck2";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  nativeBuildInputs = [ zstd ];
  strictDeps = true;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    zstd -d $src -o $out/bin/buck2
    chmod +x $out/bin/buck2

    runHook postInstall
  '';

  meta = {
    description = "Fast, hermetic, multi-language build system";
    homepage = "https://buck2.build";
    mainProgram = "buck2";
    platforms = lib.attrNames sources;
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
  };
}
