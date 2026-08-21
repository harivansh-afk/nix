# GUI apps launched at login. One owner per app (2026-08-21 startup audit):
#
# - Apps WITH a built-in "launch at login" (SMAppService) keep it and are NOT
#   listed here: Raycast, PastePal, Superhuman, Beeper, Tailscale. macOS has
#   no declarative API for those registrations (nix-darwin #1740 is open),
#   Raycast auto-reinstalls its item on launch, and duplicating them here is
#   what caused the double-launches this audit removed.
# - Apps WITHOUT one are launched by these nix agents: absolute path, never
#   the bare name - `open -a VoiceInk` resolves through LaunchServices, which
#   ranks every registered bundle with that name; stray build products can
#   and did outrank /Applications, launching a stale copy whose ad-hoc
#   cdhash misses the TCC grants.
# - VoiceInk autostart lives here (launchd), NOT in the app's own "Launch at
#   Login" toggle: that uses SMAppService, whose registration goes stale
#   every time the ad-hoc source build is re-signed.
#
# `open -a` of an already-running app is a no-op activation, but RunAtLoad
# re-fires when a plist changes at switch; keep the list to apps where a
# spurious focus steal is harmless.
{ lib, ... }:
let
  loginApps = [
    "Ghostty"
    "VoiceInk"
  ];
in
{
  launchd.user.agents = builtins.listToAttrs (
    map (app: {
      name = "open-${lib.strings.toLower (builtins.replaceStrings [ " " ] [ "-" ] app)}";
      value.serviceConfig = {
        Program = "/usr/bin/open";
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          "/Applications/${app}.app"
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
    }) loginApps
  );
}
