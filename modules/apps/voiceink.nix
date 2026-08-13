# VoiceInk, built from source into /Applications on the macbook.
#
# The prebuilt cask is the paid distribution; `make local` (no Apple Developer
# account) is the free GPLv3 path. This cannot be a pure derivation - it needs
# full Xcode (not in nixpkgs) and `make local` clones and builds whisper.cpp at
# build time (network) - so an as-user activation step shells out to the system
# Xcode, keyed on the locked `voiceink-src` rev so it only rebuilds when the
# pin changes and skips (non-fatally) if Xcode is absent.
#
# Three hard-won gotchas:
# - Upstream ships Sparkle enabled even in local builds (SUFeedURL in
#   Info.plist points at the official appcast), so the free build silently
#   auto-updates itself into the paid Developer ID distribution. The install
#   step strips the feed URL, disables update checks and re-signs.
# - Because of that, "app dir exists" is not a valid skip condition: the
#   installed bundle must also still be our neutered, locally-signed build.
# - TCC grants (Accessibility for the fn hotkey, Microphone) are keyed on the
#   app's designated requirement. Ad-hoc signatures pin the exact cdhash, so
#   every rebuild used to orphan the grants and kill the hotkey. We instead
#   sign with a machine-local self-signed identity ("VoiceInk Local Signing",
#   dedicated keychain, trusted for codeSign in the user domain - verified
#   prompt-free on macOS 26): the requirement becomes identifier +
#   certificate leaf, stable across rebuilds, so the grants are made ONCE and
#   survive every rebuild. macOS offers no way to inject the initial grant
#   (system TCC.db is SIP-protected); only that first grant is manual.
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
  identity = "VoiceInk Local Signing";
  keychain = "${home}/Library/Keychains/voiceink-signing.keychain-db";
  keychainPass = "${home}/Library/Keychains/voiceink-signing.pass";
  lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

  script = pkgs.writeShellScript "voiceink-build" ''
    set -euo pipefail
    export HOME="${home}"
    # System Xcode (/usr/bin) wins; nix git+cmake are fallbacks (whisper.cpp's
    # build-xcframework.sh needs cmake, absent alongside Xcode by default).
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
      lib.makeBinPath [
        pkgs.git
        pkgs.cmake
        pkgs.openssl
      ]
    }"

    # --- stable signing identity ------------------------------------------
    # Self-signed codeSigning cert in a dedicated, never-auto-locking
    # keychain with a random password persisted 0600 beside it. Losing
    # either file self-heals into a fresh identity (one TCC re-grant).
    # Every step is guarded, so steady state is a few cheap checks.
    ensure_identity() {
      if [ ! -f "${keychainPass}" ] || [ ! -f "${keychain}" ]; then
        security delete-keychain "${keychain}" 2>/dev/null || true
        rm -f "${keychain}" "${keychainPass}"
        (umask 077 && openssl rand -hex 32 >"${keychainPass}")
        security create-keychain -p "$(cat "${keychainPass}")" "${keychain}"
        security set-keychain-settings "${keychain}" # no auto-lock
      fi
      security unlock-keychain -p "$(cat "${keychainPass}")" "${keychain}"

      if ! security find-certificate -c "${identity}" "${keychain}" >/dev/null 2>&1; then
        tmp="$(mktemp -d)"
        openssl req -x509 -newkey rsa:2048 -days 36500 -nodes \
          -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
          -subj "/CN=${identity}" \
          -addext "keyUsage=critical,digitalSignature" \
          -addext "extendedKeyUsage=critical,codeSigning" \
          -addext "basicConstraints=critical,CA:false" 2>/dev/null
        openssl pkcs12 -export -out "$tmp/cert.p12" \
          -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:transient
        security import "$tmp/cert.p12" -k "${keychain}" -P transient -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple:,codesign: \
          -s -k "$(cat "${keychainPass}")" "${keychain}" >/dev/null
        rm -rf "$tmp"
      fi

      # codesign only finds identities in keychains on the search list.
      # NB: no `cmd | grep -q` anywhere in this script - grep -q exits on
      # first match, the writer dies of SIGPIPE and pipefail fails the
      # pipeline even on a match. Capture, then pattern-match.
      if [[ "$(security list-keychains -d user)" != *"voiceink-signing.keychain-db"* ]]; then
        local kcs=()
        while IFS= read -r line; do
          line="''${line#*\"}"
          kcs+=("''${line%\"}")
        done < <(security list-keychains -d user)
        security list-keychains -d user -s "''${kcs[@]}" "${keychain}"
      fi

      # find-identity -v = exists AND trusted; re-add trust if it was lost.
      if [[ "$(security find-identity -v -p codesigning "${keychain}")" != *"${identity}"* ]]; then
        tmp="$(mktemp -d)"
        security find-certificate -c "${identity}" -p "${keychain}" >"$tmp/cert.pem"
        security add-trusted-cert -r trustRoot -p codeSign "$tmp/cert.pem"
        rm -rf "$tmp"
      fi
    }

    sign_app() {
      security unlock-keychain -p "$(cat "${keychainPass}")" "${keychain}"
      codesign --force --deep --sign "${identity}" --keychain "${keychain}" "${app}"
      xattr -cr "${app}"
    }

    built_ok() {
      [ -d "${app}" ] || return 1
      [ "$(cat "${build}/.rev" 2>/dev/null)" = "${rev}" ] || return 1
      # No Sparkle feed = still our neutered build, not the official one
      # (Developer ID signed, keeps SUFeedURL).
      ! defaults read "${app}/Contents/Info.plist" SUFeedURL >/dev/null 2>&1 || return 1
    }
    signed_ok() {
      [[ "$(codesign -dvv "${app}" 2>&1)" == *"Authority=${identity}"* ]]
    }

    if built_ok && signed_ok; then exit 0; fi
    ensure_identity
    if built_ok; then
      # Right build, wrong/stale signature: re-sign in place, no Xcode build.
      sign_app
      echo "VoiceInk: re-signed with stable identity"
      exit 0
    fi
    command -v xcodebuild >/dev/null || { echo "VoiceInk: Xcode missing, skipping" >&2; exit 0; }

    echo "VoiceInk: building ${rev} from source (first run pulls whisper.cpp)..."
    rm -rf "${build}/src" && mkdir -p "${build}/src"
    cp -R "${src}/." "${build}/src/" && chmod -R u+w "${build}/src"
    make -C "${build}/src" local
    # `make local` also dittos a copy into ~/Downloads; one install, not two.
    rm -rf "${home}/Downloads/VoiceInk.app"

    rm -rf "${app}"
    ditto "${build}/src/.local-build/Build/Products/Debug/VoiceInk.app" "${app}"

    # Neuter Sparkle: no appcast, no automatic checks, then re-sign with the
    # stable identity (the Info.plist edit breaks the build's seal anyway).
    plutil -remove SUFeedURL "${app}/Contents/Info.plist" >/dev/null 2>&1 || true
    plutil -replace SUEnableAutomaticChecks -bool false "${app}/Contents/Info.plist"
    sign_app

    # Drop the intermediate build tree. It is NOT a cache - the build above
    # wipes and re-copies it every time - but leaving it on disk registers a
    # SECOND VoiceInk bundle (same bundle id, Sparkle still live, ~1.5G) with
    # LaunchServices. `open -a VoiceInk` resolves by NAME, so a stray copy can
    # outrank /Applications and get launched instead; its signature differs,
    # so the TCC grants (Accessibility/Microphone) silently do not apply and
    # the hotkey + mic appear broken. Unregister, then delete.
    ${lsregister} -u "${build}/src/.local-build/Build/Products/Debug/VoiceInk.app" >/dev/null 2>&1 || true
    rm -rf "${build}/src"
    ${lsregister} -f "${app}" >/dev/null 2>&1 || true

    printf '%s' "${rev}" >"${build}/.rev"
    echo "VoiceInk: installed ${rev}"
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${script} || echo "warning: VoiceInk build failed" >&2
  '';
}
