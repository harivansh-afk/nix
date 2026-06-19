# VoiceInk, built from source into /Applications on the macbook.
#
# The prebuilt cask is the paid distribution; `make local` (ad-hoc signing, no
# Apple Developer account) is the free GPLv3 path. This cannot be a pure
# derivation - it needs full Xcode (not in nixpkgs) and `make local` clones and
# builds whisper.cpp at build time (network) - so an as-user activation step
# shells out to the system Xcode, keyed on the locked `voiceink-src` rev so it
# only rebuilds when the pin changes and skips (non-fatally) if Xcode is absent.
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

    if [ "$(cat "${build}/.rev" 2>/dev/null)" = "${rev}" ] && [ -d "${app}" ]; then exit 0; fi
    command -v xcodebuild >/dev/null || { echo "VoiceInk: Xcode missing, skipping" >&2; exit 0; }

    echo "VoiceInk: building ${rev} from source (first run pulls whisper.cpp)..."
    rm -rf "${build}/src" && mkdir -p "${build}/src"
    cp -R "${src}/." "${build}/src/" && chmod -R u+w "${build}/src"
    make -C "${build}/src" local

    rm -rf "${app}"
    ditto "${build}/src/.local-build/Build/Products/Debug/VoiceInk.app" "${app}"
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
