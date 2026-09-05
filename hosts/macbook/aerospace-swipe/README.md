# AeroSpace trackpad switching

`services.nix` runs the pinned aerospace-swipe app through a nix-darwin user
agent. Three-finger swipes left select the next occupied workspace on the
focused monitor; swipes right select the previous one. Switching wraps at the
ends. Settings live in `dots/aerospace-swipe/config.json`; restart the agent
after editing them.

After merging, run `just switch`, then grant AerospaceSwipe Accessibility
access in System Settings > Privacy & Security > Accessibility. The app is
included in the system applications. If the changed trackpad preferences do
not take effect immediately, log out and back in. Native three-finger horizontal
navigation is disabled for both built-in and Bluetooth trackpads, and page
navigation uses two fingers. Native desktop switching can remain on four
fingers. Mission Control and vertical gestures are unchanged.

The package removes upstream's `-march=native` and signs the bundle after Nix
fixups. It also suppresses upstream's independent app launch after Accessibility
permission is granted: the process exits and launchd's `KeepAlive` restarts it.
This keeps one service owner. CLI fallback has the matching AeroSpace on PATH.

This adds gesture-triggered AeroSpace switching, without native Spaces or the
macOS desktop slide animation. A physical swipe check after granting access is
required to verify the complete interaction.
