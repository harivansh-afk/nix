#!/usr/bin/env bash
# Build and sign Mux.app. Inputs from the nix wrapper: MUX_SRC, MUX_REV,
# GHOSTTY_SRC, GHOSTTY_REV, MUXD (package with bin/muxd, bin/mux-attach),
# INFO_PLIST.
#
# Signs with the "mux-dev" identity in mux-dev.keychain-db, the keychain
# mux's own scripts/make-app.sh uses, so TCC grants survive rebuilds. Created
# here rather than by mux's dev-sign-setup.sh: its `find-identity -v` check
# hides untrusted self-signed certs and would recreate the identity every run.
set -euo pipefail

rev="$MUX_REV-$GHOSTTY_REV"
build="$HOME/Library/Caches/mux-build"
app="/Applications/Mux.app"
identity="mux-dev"
keychain="$HOME/Library/Keychains/mux-dev.keychain-db"
keychain_pass="mux-dev"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
mkdir -p "$build"

# No `cmd | grep -q` here: grep exits on the first match, the writer dies of
# SIGPIPE and pipefail fails the pipeline. Capture, then pattern-match.
ensure_identity() {
  if [ ! -f "$keychain" ]; then
    security create-keychain -p "$keychain_pass" "$keychain"
    security set-keychain-settings "$keychain"
  fi
  security unlock-keychain -p "$keychain_pass" "$keychain"

  if ! security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -days 36500 -nodes \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
      -subj "/CN=$identity" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" \
      -addext "basicConstraints=critical,CA:false" 2>/dev/null
    openssl pkcs12 -export -legacy -out "$tmp/cert.p12" \
      -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:transient
    security import "$tmp/cert.p12" -k "$keychain" -P transient -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
      -s -k "$keychain_pass" "$keychain" >/dev/null
    rm -rf "$tmp"
  fi

  if [[ "$(security list-keychains -d user)" != *"mux-dev.keychain-db"* ]]; then
    local kcs=()
    while IFS= read -r line; do
      line="${line#*\"}"
      kcs+=("${line%\"}")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "${kcs[@]}" "$keychain"
  fi

  if [[ "$(security find-identity -v -p codesigning "$keychain")" != *"$identity"* ]]; then
    tmp="$(mktemp -d)"
    security find-certificate -c "$identity" -p "$keychain" >"$tmp/cert.pem"
    security add-trusted-cert -r trustRoot -p codeSign "$tmp/cert.pem"
    rm -rf "$tmp"
  fi
}

sign_app() {
  security unlock-keychain -p "$keychain_pass" "$keychain"
  codesign --force --deep --sign "$identity" --keychain "$keychain" "$app"
  xattr -cr "$app"
}

built_ok() {
  [ -d "$app" ] && [ ! -L "$app" ] || return 1
  [ "$(cat "$build/.rev" 2>/dev/null)" = "$rev" ] || return 1
}

signed_ok() {
  [[ "$(codesign -dvv "$app" 2>&1)" == *"Authority=$identity"* ]]
}

if built_ok && signed_ok; then exit 0; fi
ensure_identity
if built_ok; then
  sign_app
  echo "Mux: re-signed"
  exit 0
fi
command -v xcodebuild >/dev/null || {
  echo "Mux: Xcode missing, skipping" >&2
  exit 0
}

# GhosttyKit.xcframework + ghostty's share/ (terminfo, shell integration),
# cached per ghostty rev. ReleaseFast: a Debug libghostty os_logs every IO
# message and freezes under load.
gk="$build/ghostty-$GHOSTTY_REV"
if [ ! -d "$gk/macos/GhosttyKit.xcframework" ] || [ ! -d "$gk/zig-out/share/ghostty" ]; then
  echo "Mux: building GhosttyKit at ghostty $GHOSTTY_REV..."
  if [ ! -d "$gk" ]; then
    mkdir -p "$gk"
    cp -R "$GHOSTTY_SRC/." "$gk/" && chmod -R u+w "$gk"
  fi
  export ZIG_GLOBAL_CACHE_DIR="$build/zig-cache"
  (cd "$gk" && zig build -Demit-xcframework -Dxcframework-target=native -Doptimize=ReleaseFast)
  [ -d "$gk/zig-out/share/ghostty" ] || (cd "$gk" && zig build -Doptimize=ReleaseFast)
  for old in "$build"/ghostty-*; do
    [ "$old" = "$gk" ] || rm -rf "$old"
  done
fi

echo "Mux: building $MUX_REV..."
appsrc="$build/app"
rm -rf "$appsrc" && mkdir -p "$appsrc"
cp -R "$MUX_SRC/app/." "$appsrc/" && chmod -R u+w "$appsrc"
mkdir -p "$appsrc/GhosttyKit"
cp -R "$gk/macos/GhosttyKit.xcframework" "$appsrc/GhosttyKit/"
swift build -c release --package-path "$appsrc" --scratch-path "$build/swift-build"
bin="$(swift build -c release --package-path "$appsrc" --scratch-path "$build/swift-build" --show-bin-path)/Mux"

# Layout as in mux's scripts/make-app.sh; ghostty resolves terminfo as the
# sibling of GHOSTTY_RESOURCES_DIR (Resources/ghostty).
bundle="$build/Mux.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/Mux"
cp "$MUXD/bin/muxd" "$MUXD/bin/mux-attach" "$bundle/Contents/MacOS/"
chmod u+w "$bundle/Contents/MacOS/"*
cp "$MUX_SRC/app/Assets/Mux.icns" "$bundle/Contents/Resources/Mux.icns"
cp -R "$gk/zig-out/share/ghostty" "$bundle/Contents/Resources/ghostty"
cp -R "$gk/zig-out/share/terminfo" "$bundle/Contents/Resources/terminfo"
cp "$INFO_PLIST" "$bundle/Contents/Info.plist"

rm -rf "$app"
ditto "$bundle" "$app"
sign_app

"$lsregister" -u "$bundle" >/dev/null 2>&1 || true
rm -rf "$bundle" "$appsrc"
"$lsregister" -f "$app" >/dev/null 2>&1 || true

printf '%s' "$rev" >"$build/.rev"
echo "Mux: installed $rev"
