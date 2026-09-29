{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:
let
  targets = {
    aarch64-linux = {
      triple = "aarch64-unknown-linux-musl";
      hash = "sha256-SO+h8/zoz/J1z1dReryHyWbAWYLEWJFSrY9YkNfjYcg=";
    };
    x86_64-linux = {
      triple = "x86_64-unknown-linux-musl";
      hash = "sha256-HckKjjKtOtDjrQ3PBm+1e/yARt7CdRj6fQoYIr9tEdg=";
    };
    aarch64-darwin = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-A52ngdIiNLOwwyjaJQwicPerT3I+LTtQLFbKFC6/uCc=";
    };
  };
  target = targets.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "baml-cli";
  version = "0.20.2-nightly.20260923.a";

  src = fetchurl {
    url = "https://github.com/BoundaryML/baml/releases/download/baml-language-${finalAttrs.version}/baml-language-${finalAttrs.version}-${target.triple}.tar.gz";
    inherit (target) hash;
  };
  sourceRoot = ".";
  nativeBuildInputs = [ makeWrapper ];
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r bin assets VERSION "$out/"
    wrapProgram "$out/bin/baml-cli" \
      --set BAML_CLI_ALLOW_DIRECT 1 \
      --set-default BAML_TELEMETRY_DISABLED 1 \
      --set-default BAML_TELEMETRY off
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export BAML_HOME="$TMPDIR/baml" BAML_CACHE_DIR="$TMPDIR/cache"
    mkdir -p "$BAML_HOME" "$BAML_CACHE_DIR"
    "$out/bin/baml-cli" --version
    "$out/bin/baml-cli" lsp --help
    runHook postInstallCheck
  '';

  meta = {
    description = "BAML compiler and language server";
    homepage = "https://github.com/BoundaryML/baml";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "baml-cli";
    platforms = builtins.attrNames targets;
  };
})
