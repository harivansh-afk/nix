#!/usr/bin/env bash
# Build, neuter and sign VoiceInk. Inputs from the nix wrapper: SRC (source
# tree), PATCH (streaming-provider patch), REV (rebuild key).
#
# Upstream local builds keep Sparkle's SUFeedURL, so an untouched build
# auto-updates itself into the paid Developer ID release: the feed is
# stripped and checks disabled before signing, and a bundle with the feed
# still present is treated as not ours.
#
# TCC grants (Accessibility for the hotkey, Microphone) are keyed on the
# designated requirement. Ad-hoc signing pins the exact cdhash and orphans
# them on every rebuild, so the bundle is signed with a self-signed identity
# in its own keychain: identifier + certificate leaf, stable across rebuilds.
# The first grant is manual (TCC.db is SIP-protected).
set -euo pipefail

build="$HOME/Library/Caches/voiceink-build"
app="/Applications/VoiceInk.app"
identity="VoiceInk Local Signing"
keychain="$HOME/Library/Keychains/voiceink-signing.keychain-db"
keychain_pass="$HOME/Library/Keychains/voiceink-signing.pass"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# No `cmd | grep -q` here: grep exits on the first match, the writer dies of
# SIGPIPE and pipefail fails the pipeline. Capture, then pattern-match.
ensure_identity() {
  if [ ! -f "$keychain_pass" ] || [ ! -f "$keychain" ]; then
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -f "$keychain" "$keychain_pass"
    (umask 077 && openssl rand -hex 32 >"$keychain_pass")
    security create-keychain -p "$(cat "$keychain_pass")" "$keychain"
    security set-keychain-settings "$keychain" # never auto-lock
  fi
  security unlock-keychain -p "$(cat "$keychain_pass")" "$keychain"

  if ! security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -days 36500 -nodes \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
      -subj "/CN=$identity" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" \
      -addext "basicConstraints=critical,CA:false" 2>/dev/null
    openssl pkcs12 -export -out "$tmp/cert.p12" \
      -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:transient
    security import "$tmp/cert.p12" -k "$keychain" -P transient -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
      -s -k "$(cat "$keychain_pass")" "$keychain" >/dev/null
    rm -rf "$tmp"
  fi

  # codesign only searches keychains on the user search list.
  if [[ "$(security list-keychains -d user)" != *"voiceink-signing.keychain-db"* ]]; then
    local kcs=()
    while IFS= read -r line; do
      line="${line#*\"}"
      kcs+=("${line%\"}")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "${kcs[@]}" "$keychain"
  fi

  # find-identity -v lists only trusted identities; re-add trust if lost.
  if [[ "$(security find-identity -v -p codesigning "$keychain")" != *"$identity"* ]]; then
    tmp="$(mktemp -d)"
    security find-certificate -c "$identity" -p "$keychain" >"$tmp/cert.pem"
    security add-trusted-cert -r trustRoot -p codeSign "$tmp/cert.pem"
    rm -rf "$tmp"
  fi
}

sign_app() {
  security unlock-keychain -p "$(cat "$keychain_pass")" "$keychain"
  codesign --force --deep --sign "$identity" --keychain "$keychain" "$app"
  xattr -cr "$app"
}

built_ok() {
  [ -d "$app" ] || return 1
  [ "$(cat "$build/.rev" 2>/dev/null)" = "$REV" ] || return 1
  ! defaults read "$app/Contents/Info.plist" SUFeedURL >/dev/null 2>&1 || return 1
}

signed_ok() {
  [[ "$(codesign -dvv "$app" 2>&1)" == *"Authority=$identity"* ]]
}

if built_ok && signed_ok; then exit 0; fi
ensure_identity
if built_ok; then
  sign_app
  echo "VoiceInk: re-signed"
  exit 0
fi
command -v xcodebuild >/dev/null || {
  echo "VoiceInk: Xcode missing, skipping" >&2
  exit 0
}

echo "VoiceInk: building $REV..."
rm -rf "$build/src" && mkdir -p "$build/src"
cp -R "$SRC/." "$build/src/" && chmod -R u+w "$build/src"
patch -p1 -d "$build/src" <"$PATCH"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null
make -C "$build/src" local LOCAL_CODESIGN_IDENTITY="$identity"
rm -rf "$HOME/Downloads/VoiceInk.app" # `make local` dittos a second copy there

rm -rf "$app"
ditto "$build/src/.local-build/Build/Products/Debug/VoiceInk.app" "$app"
plutil -remove SUFeedURL "$app/Contents/Info.plist" >/dev/null 2>&1 || true
plutil -replace SUEnableAutomaticChecks -bool false "$app/Contents/Info.plist"
sign_app

# The intermediate bundle is a second LaunchServices registration of the same
# name; `open -a VoiceInk` can pick it over /Applications, and its signature
# misses the TCC grants. Unregister it, then delete it.
"$lsregister" -u "$build/src/.local-build/Build/Products/Debug/VoiceInk.app" >/dev/null 2>&1 || true
rm -rf "$build/src"
"$lsregister" -f "$app" >/dev/null 2>&1 || true

printf '%s' "$REV" >"$build/.rev"
echo "VoiceInk: installed $REV"
