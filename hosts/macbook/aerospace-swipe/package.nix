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
    rev = "16aad5a5ad678335a7593a2afaa473816c278c5f";
    hash = "sha256-VsqhN5hUZk3ehVwShvL+4WClvLU+CJGGAnHyJKAwteo=";
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
