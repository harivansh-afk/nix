# aerospace pinned to the latest upstream release, independent of nixpkgs
# channel lag: the WM should not wait on a full `nix flake update nixpkgs`
# world rebuild for a version bump.
#
# Patch policy (user-decided 2026-08-09; the betterspace fork repo was
# created and deleted the same day in favor of this file): performance
# patches against upstream live in ./patches/ and are maintained
# rebase-style on top of the pinned release tag. nixpkgs (and this
# override) repackage upstream's PREBUILT release zip, so .patch files
# cannot be applied here directly - shipping a real source patch means
# building AeroSpace.app locally with Xcode (`swift build -c release` over
# an upstream checkout with ./patches/ applied), zipping the result,
# uploading it as a release asset on git.harivan.sh, and pointing `src` at
# that url+hash instead of the GitHub zip. Until the first patch lands,
# this is only a version pin.
#
# First patch target: upstream issue #1615 - the main thread fans out
# refresh requests to every per-app AX thread and waits for ALL of them
# before layouting, so one slow app (Electron, a REPL, Zoom) stalls every
# window operation. The scoped fix is a reactive, non-blocking refresh.
{ prev }:
prev.aerospace.overrideAttrs (_old: rec {
  version = "0.21.3-Beta";
  src = prev.fetchzip {
    url = "https://github.com/nikitabobko/AeroSpace/releases/download/v${version}/AeroSpace-v${version}.zip";
    # hash from nixpkgs master's aerospace 0.21.3-Beta packaging (same
    # fetcher, same url), where this pin will eventually catch up.
    hash = "sha256-JHXtF3IKUbge7z2cMBi4L9IruiByNPCIKugLe4ymvys=";
  };
})
