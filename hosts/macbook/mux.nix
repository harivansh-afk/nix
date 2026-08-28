# Mux.app, built from the flake's pinned mux rev into /Applications.
#
# The app and the org.nixos.muxd agent (./muxd.nix) share one rev: the
# bundled muxd and mux-attach are the mux flake's nix package.
#
# Not a pure derivation: the app needs full Xcode (swift build against
# AppKit/Metal, and ghostty's xcframework build compiles Metal shaders
# through xcrun). Like voiceink.nix, an as-user activation step builds with
# the system Xcode, keyed on mux rev + ghostty rev, and skips without Xcode.
#
# Signing uses the "mux-dev" identity in mux-dev.keychain-db, the keychain
# mux's scripts/make-app.sh uses, so TCC grants survive rebuilds. It is
# created here rather than by mux's dev-sign-setup.sh, whose presence check
# (`find-identity -v`) hides untrusted self-signed certs and would recreate
# the identity on every run.
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  mux = inputs.mux;
  ghostty = mux.inputs.ghostty;
  muxPkg = mux.packages.${pkgs.stdenv.hostPlatform.system}.muxd;
  rev = "${mux.rev}-${ghostty.rev}";
  home = "/Users/${username}";
  build = "${home}/Library/Caches/mux-build";
  app = "/Applications/Mux.app";
  identity = "mux-dev";
  keychain = "${home}/Library/Keychains/mux-dev.keychain-db";
  keychainPass = "mux-dev";
  lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

  script = pkgs.writeShellScript "mux-app-build" ''
        set -euo pipefail
        export HOME="${home}"
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
          lib.makeBinPath [
            pkgs.zig_0_16
            pkgs.openssl
          ]
        }"
        mkdir -p "${build}"

        ensure_identity() {
          if [ ! -f "${keychain}" ]; then
            security create-keychain -p "${keychainPass}" "${keychain}"
            security set-keychain-settings "${keychain}"
          fi
          security unlock-keychain -p "${keychainPass}" "${keychain}"

          if ! security find-certificate -c "${identity}" "${keychain}" >/dev/null 2>&1; then
            tmp="$(mktemp -d)"
            openssl req -x509 -newkey rsa:2048 -days 36500 -nodes \
              -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
              -subj "/CN=${identity}" \
              -addext "keyUsage=critical,digitalSignature" \
              -addext "extendedKeyUsage=critical,codeSigning" \
              -addext "basicConstraints=critical,CA:false" 2>/dev/null
            openssl pkcs12 -export -legacy -out "$tmp/cert.p12" \
              -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:transient
            security import "$tmp/cert.p12" -k "${keychain}" -P transient -T /usr/bin/codesign
            security set-key-partition-list -S apple-tool:,apple:,codesign: \
              -s -k "${keychainPass}" "${keychain}" >/dev/null
            rm -rf "$tmp"
          fi

          # codesign only finds identities in keychains on the search list.
          if [[ "$(security list-keychains -d user)" != *"mux-dev.keychain-db"* ]]; then
            local kcs=()
            while IFS= read -r line; do
              line="''${line#*\"}"
              kcs+=("''${line%\"}")
            done < <(security list-keychains -d user)
            security list-keychains -d user -s "''${kcs[@]}" "${keychain}"
          fi

          if [[ "$(security find-identity -v -p codesigning "${keychain}")" != *"${identity}"* ]]; then
            tmp="$(mktemp -d)"
            security find-certificate -c "${identity}" -p "${keychain}" >"$tmp/cert.pem"
            security add-trusted-cert -r trustRoot -p codeSign "$tmp/cert.pem"
            rm -rf "$tmp"
          fi
        }

        sign_app() {
          security unlock-keychain -p "${keychainPass}" "${keychain}"
          codesign --force --deep --sign "${identity}" --keychain "${keychain}" "${app}"
          xattr -cr "${app}"
        }

        built_ok() {
          [ -d "${app}" ] && [ ! -L "${app}" ] || return 1
          [ "$(cat "${build}/.rev" 2>/dev/null)" = "${rev}" ] || return 1
        }
        signed_ok() {
          [[ "$(codesign -dvv "${app}" 2>&1)" == *"Authority=${identity}"* ]]
        }

        if built_ok && signed_ok; then exit 0; fi
        ensure_identity
        if built_ok; then
          sign_app
          echo "Mux: re-signed"
          exit 0
        fi
        command -v xcodebuild >/dev/null || { echo "Mux: Xcode missing, skipping" >&2; exit 0; }

        # GhosttyKit.xcframework + ghostty's share/ (terminfo, shell integration),
        # cached per ghostty rev. ReleaseFast: a Debug libghostty os_logs every IO
        # message and freezes under load (mux's scripts/fetch-ghosttykit.sh).
        gk="${build}/ghostty-${ghostty.rev}"
        if [ ! -d "$gk/macos/GhosttyKit.xcframework" ] || [ ! -d "$gk/zig-out/share/ghostty" ]; then
          echo "Mux: building GhosttyKit at ghostty ${ghostty.rev}..."
          if [ ! -d "$gk" ]; then
            mkdir -p "$gk"
            cp -R "${ghostty}/." "$gk/" && chmod -R u+w "$gk"
          fi
          export ZIG_GLOBAL_CACHE_DIR="${build}/zig-cache"
          (cd "$gk" && zig build -Demit-xcframework -Dxcframework-target=native -Doptimize=ReleaseFast)
          [ -d "$gk/zig-out/share/ghostty" ] || (cd "$gk" && zig build -Doptimize=ReleaseFast)
          for old in "${build}"/ghostty-*; do
            [ "$old" = "$gk" ] || rm -rf "$old"
          done
        fi

        echo "Mux: building ${mux.rev}..."
        appsrc="${build}/app"
        rm -rf "$appsrc" && mkdir -p "$appsrc"
        cp -R "${mux}/app/." "$appsrc/" && chmod -R u+w "$appsrc"
        mkdir -p "$appsrc/GhosttyKit"
        cp -R "$gk/macos/GhosttyKit.xcframework" "$appsrc/GhosttyKit/"
        swift build -c release --package-path "$appsrc" --scratch-path "${build}/swift-build"
        bin="$(swift build -c release --package-path "$appsrc" --scratch-path "${build}/swift-build" --show-bin-path)/Mux"

        # Layout and Info.plist as in mux's scripts/make-app.sh. Ghostty resolves
        # terminfo as the sibling of GHOSTTY_RESOURCES_DIR (Resources/ghostty).
        bundle="${build}/Mux.app"
        rm -rf "$bundle"
        mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
        cp "$bin" "$bundle/Contents/MacOS/Mux"
        cp "${muxPkg}/bin/muxd" "${muxPkg}/bin/mux-attach" "$bundle/Contents/MacOS/"
        chmod u+w "$bundle/Contents/MacOS/"*
        cp "${mux}/app/Assets/Mux.icns" "$bundle/Contents/Resources/Mux.icns"
        cp -R "$gk/zig-out/share/ghostty" "$bundle/Contents/Resources/ghostty"
        cp -R "$gk/zig-out/share/terminfo" "$bundle/Contents/Resources/terminfo"
        cat >"$bundle/Contents/Info.plist" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key><string>sh.harivan.mux</string>
      <key>CFBundleName</key><string>mux</string>
      <key>CFBundleExecutable</key><string>Mux</string>
      <key>CFBundleIconFile</key><string>Mux</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.2.0</string>
      <key>LSMinimumSystemVersion</key><string>14.0</string>
      <key>NSHighResolutionCapable</key><true/>
      <key>NSPrincipalClass</key><string>NSApplication</string>
    </dict>
    </plist>
    PLIST

        rm -rf "${app}"
        ditto "$bundle" "${app}"
        sign_app

        # One registered Mux bundle: unregister and drop the intermediate.
        ${lsregister} -u "$bundle" >/dev/null 2>&1 || true
        rm -rf "$bundle" "$appsrc"
        ${lsregister} -f "${app}" >/dev/null 2>&1 || true

        printf '%s' "${rev}" >"${build}/.rev"
        echo "Mux: installed ${rev}"
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${script} || echo "warning: Mux build failed" >&2
  '';
}
