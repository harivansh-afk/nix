{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation {
  pname = "aerospace-swipe";
  version = "0-unstable-2026-09-05";

  src = fetchFromGitHub {
    owner = "acsandmann";
    repo = "aerospace-swipe";
    rev = "fecab07757d2e50345afeb361d16107444711a40";
    hash = "sha256-tLWN5NpbPgEviqXi3+1o1jmyWFFEfWITLvuHvV2l3XY=";
  };

  postPatch = ''
    substituteInPlace makefile \
      --replace-fail "-march=native" "" \
      --replace-fail 'codesign --entitlements' '/usr/bin/codesign --entitlements'
    substituteInPlace src/main.m \
      --replace-fail 'signal(SIGCHLD, SIG_IGN);' 'signal(SIGCHLD, SIG_DFL);' \
      --replace-fail '[[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:bundlePath] configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];' '(void)bundlePath;'
  '';

  makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
  buildFlags = [ "bundle" ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R AerospaceSwipe.app $out/Applications/
    runHook postInstall
  '';
  postFixup = ''
    /usr/bin/codesign --force --entitlements accessibility.entitlements --sign - $out/Applications/AerospaceSwipe.app
  '';

  meta = {
    description = "Switch AeroSpace workspaces with trackpad swipes";
    homepage = "https://github.com/acsandmann/aerospace-swipe";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
