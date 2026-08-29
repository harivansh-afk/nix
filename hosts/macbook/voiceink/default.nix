# VoiceInk built from source into /Applications (the cask is the paid build).
# Needs the system Xcode and network, so it runs as an activation step keyed
# on the pinned rev + patch; see build.sh for the signing and Sparkle story.
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  src = inputs.voiceink-src;
  patch = ./streaming-provider.patch;
  rev = "${src.rev or src.narHash or "unknown"}-${
    builtins.substring 0 12 (builtins.hashFile "sha256" patch)
  }";
  home = "/Users/${username}";

  build = pkgs.writeShellScript "voiceink-build" ''
    export HOME=${lib.escapeShellArg home}
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
      lib.makeBinPath [
        pkgs.git
        pkgs.cmake
        pkgs.openssl
      ]
    }"
    export SRC=${src} PATCH=${patch} REV=${lib.escapeShellArg rev}
    exec ${./build.sh}
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${build} || echo "warning: VoiceInk build failed" >&2
  '';
}
