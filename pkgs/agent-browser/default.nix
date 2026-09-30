{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "agent-browser";
  version = "0.38.1";
  src = fetchurl {
    url = "https://github.com/vercel-labs/agent-browser/releases/download/v${finalAttrs.version}/agent-browser-linux-musl-arm64";
    hash = "sha256-YNwfSbNlaJiojjypg0FeH07NEDQzySTx/07BGDfM2gc=";
  };
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/agent-browser
    cp -r ${finalAttrs.passthru.source}/skills $out/skills
    cp -r ${finalAttrs.passthru.source}/skill-data $out/skill-data
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/agent-browser --version
    $out/bin/agent-browser skills get core > /dev/null
  '';
  passthru.source = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    tag = "v${finalAttrs.version}";
    hash = "sha256-C+XplCHOdFDQGPUnrCDuq7U4LkAX0QB3fC4uVA8o11w=";
  };
  meta = {
    description = "Upstream agent-browser CLI with strict shared-CDP tab pinning";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "agent-browser";
    platforms = [ "aarch64-linux" ];
  };
})
