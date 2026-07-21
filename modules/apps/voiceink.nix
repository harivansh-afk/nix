# VoiceInk, built from source into /Applications on the macbook.
#
# The prebuilt cask is the paid distribution; `make local` (ad-hoc signing, no
# Apple Developer account) is the free GPLv3 path. This cannot be a pure
# derivation - it needs full Xcode (not in nixpkgs) and `make local` clones and
# builds whisper.cpp at build time (network) - so an as-user activation step
# shells out to the system Xcode, keyed on the locked `voiceink-src` rev so it
# only rebuilds when the pin changes and skips (non-fatally) if Xcode is absent.
#
# Two hard-won gotchas:
# - Upstream ships Sparkle enabled even in local builds (SUFeedURL in
#   Info.plist points at the official appcast), so the free build silently
#   auto-updates itself into the paid Developer ID distribution. The install
#   step strips the feed URL, disables update checks and re-signs ad-hoc.
# - Because of that, "app dir exists" is not a valid skip condition: the
#   installed bundle must also still be our neutered ad-hoc build.
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  src = inputs.voiceink-src;
  rev = src.rev or src.narHash or "unknown";
  home = "/Users/${username}";
  build = "${home}/Library/Caches/voiceink-build";
  app = "/Applications/VoiceInk.app";

  script = pkgs.writeShellScript "voiceink-build" ''
    set -euo pipefail
    export HOME="${home}"
    # System Xcode (/usr/bin) wins; nix git+cmake are fallbacks (whisper.cpp's
    # build-xcframework.sh needs cmake, absent alongside Xcode by default).
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
      lib.makeBinPath [
        pkgs.git
        pkgs.cmake
      ]
    }"

    installed_ok() {
      [ -d "${app}" ] || return 1
      [ "$(cat "${build}/.rev" 2>/dev/null)" = "${rev}" ] || return 1
      # Still our build? Ad-hoc signature and no Sparkle feed. The official
      # build is Developer ID signed and keeps SUFeedURL.
      codesign -dv "${app}" 2>&1 | grep -q 'Signature=adhoc' || return 1
      ! defaults read "${app}/Contents/Info.plist" SUFeedURL >/dev/null 2>&1 || return 1
    }
    if installed_ok; then exit 0; fi
    command -v xcodebuild >/dev/null || { echo "VoiceInk: Xcode missing, skipping" >&2; exit 0; }

    echo "VoiceInk: building ${rev} from source (first run pulls whisper.cpp)..."
    rm -rf "${build}/src" && mkdir -p "${build}/src"
    cp -R "${src}/." "${build}/src/" && chmod -R u+w "${build}/src"
    make -C "${build}/src" local
    # `make local` also dittos a copy into ~/Downloads; one install, not two.
    rm -rf "${home}/Downloads/VoiceInk.app"

    rm -rf "${app}"
    ditto "${build}/src/.local-build/Build/Products/Debug/VoiceInk.app" "${app}"

    # Neuter Sparkle: no appcast, no automatic checks, then re-sign ad-hoc
    # (the Info.plist edit breaks the build's seal).
    plutil -remove SUFeedURL "${app}/Contents/Info.plist" >/dev/null 2>&1 || true
    plutil -replace SUEnableAutomaticChecks -bool false "${app}/Contents/Info.plist"
    codesign --force --deep --sign - "${app}"

    xattr -cr "${app}"
    printf '%s' "${rev}" >"${build}/.rev"
    echo "VoiceInk: installed ${rev}"
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${script} || echo "warning: VoiceInk build failed" >&2
  '';
}
