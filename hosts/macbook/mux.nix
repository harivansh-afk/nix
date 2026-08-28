# Mux.app, built from source into /Applications on the macbook.
#
# Until 2026-08-28 /Applications/Mux.app was a symlink into the checkout's
# app/.build, so the installed app was whatever `scripts/make-app.sh` last
# left there, at whatever rev the working tree happened to be on. This
# module builds it from the flake's pinned mux rev (the same one the
# org.nixos.muxd launchd agent runs, hosts/macbook/muxd.nix), so the app,
# its bundled muxd, and the daemon are provably one build.
#
# Not a pure derivation: the app needs full Xcode (swift build against
# AppKit/Metal, and ghostty's xcframework build compiles Metal shaders
# through xcrun), which nixpkgs cannot provide. As with voiceink.nix, an
# as-user activation step shells out to the system Xcode, keyed on the mux
# rev + ghostty rev so it only rebuilds when a pin moves, and skips
# (non-fatally) if Xcode is absent.
#
# Pieces, in build order:
# - GhosttyKit.xcframework + ghostty's share/ (terminfo, shell
#   integration): `zig build -Demit-xcframework` in ghostty at the rev mux
#   pins, with nixpkgs' zig 0.16. Cached per ghostty rev; this is the slow
#   step and a rare one. ReleaseFast is not optional (a Debug libghostty
#   os_logs every IO message and freezes under nvim scroll, per mux's
#   scripts/fetch-ghosttykit.sh).
# - Mux binary: `swift build -c release` on a writable copy of mux/app.
# - muxd + mux-attach: from the mux flake's nix package, not cargo. Same
#   store path the launchd agent runs.
# - Bundle assembly and Info.plist mirror scripts/make-app.sh.
# - Signing: the "mux-dev" identity in mux-dev.keychain-db, the keychain
#   scripts/make-app.sh already uses (known password by design). Made
#   idempotently here rather than via mux's dev-sign-setup.sh, whose
#   presence check uses `find-identity -v`, which hides untrusted
#   self-signed certs and so recreates the identity on every run. A stable
#   identity is what keeps TCC grants across rebuilds; this also trusts it
#   for codeSign so `-v` sees it.
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
        # System Xcode (/usr/bin) wins for swift, codesign, xcrun; nix supplies
        # zig 0.16 for ghostty and openssl for the identity.
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
          lib.makeBinPath [
            pkgs.zig_0_16
            pkgs.openssl
            pkgs.git
          ]
        }"
        mkdir -p "${build}"

        # --- stable signing identity ------------------------------------------
        ensure_identity() {
          if [ ! -f "${keychain}" ]; then
            security create-keychain -p "${keychainPass}" "${keychain}"
            security set-keychain-settings "${keychain}" # no auto-lock
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
          # No `cmd | grep -q` under pipefail (grep exits on first match, the
          # writer dies of SIGPIPE): capture, then pattern-match.
          if [[ "$(security list-keychains -d user)" != *"mux-dev.keychain-db"* ]]; then
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
          security unlock-keychain -p "${keychainPass}" "${keychain}"
          codesign --force --deep --sign "${identity}" --keychain "${keychain}" "${app}"
          xattr -cr "${app}"
        }

        built_ok() {
          # A real bundle, not the old symlink into the checkout.
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
          echo "Mux: re-signed with stable identity"
          exit 0
        fi
        command -v xcodebuild >/dev/null || { echo "Mux: Xcode missing, skipping" >&2; exit 0; }

        # --- GhosttyKit + ghostty resources, cached per ghostty rev -----------
        gk="${build}/ghostty-${ghostty.rev}"
        if [ ! -d "$gk/macos/GhosttyKit.xcframework" ] || [ ! -d "$gk/zig-out/share/ghostty" ]; then
          echo "Mux: building GhosttyKit at ghostty ${ghostty.rev} (zig, minutes)..."
          rm -rf "$gk" && mkdir -p "$gk"
          cp -R "${ghostty}/." "$gk/" && chmod -R u+w "$gk"
          # zig's package cache: real cache, keyed by content, survives revs.
          export ZIG_GLOBAL_CACHE_DIR="${build}/zig-cache"
          (cd "$gk" && zig build -Demit-xcframework -Dxcframework-target=native -Doptimize=ReleaseFast)
          [ -d "$gk/zig-out/share/ghostty" ] || (cd "$gk" && zig build -Doptimize=ReleaseFast)
          # Older ghostty revs' trees are dead weight once the pin moves.
          for old in "${build}"/ghostty-*; do
            [ "$old" = "$gk" ] || rm -rf "$old"
          done
        fi

        # --- Mux binary ---------------------------------------------------------
        echo "Mux: building ${mux.rev} from source..."
        appsrc="${build}/app"
        rm -rf "$appsrc" && mkdir -p "$appsrc"
        cp -R "${mux}/app/." "$appsrc/" && chmod -R u+w "$appsrc"
        mkdir -p "$appsrc/GhosttyKit"
        cp -R "$gk/macos/GhosttyKit.xcframework" "$appsrc/GhosttyKit/"
        # .build is SwiftPM's incremental cache; keep it across rebuilds.
        swift build -c release --package-path "$appsrc" --scratch-path "${build}/swift-build"
        bin="$(swift build -c release --package-path "$appsrc" --scratch-path "${build}/swift-build" --show-bin-path)/Mux"

        # --- bundle -------------------------------------------------------------
        bundle="${build}/Mux.app"
        rm -rf "$bundle"
        mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
        cp "$bin" "$bundle/Contents/MacOS/Mux"
        cp "${muxPkg}/bin/muxd" "${muxPkg}/bin/mux-attach" "$bundle/Contents/MacOS/"
        chmod u+w "$bundle/Contents/MacOS/"*
        cp "${mux}/app/Assets/Mux.icns" "$bundle/Contents/Resources/Mux.icns"
        # GHOSTTY_RESOURCES_DIR points at Resources/ghostty; ghostty derives the
        # terminfo db as its SIBLING Resources/terminfo. Both, or TERM breaks.
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

        # --- install ------------------------------------------------------------
        # The old install was a symlink into ~/Documents/Git/mux/app/.build;
        # rm -rf on a symlink removes the link, not the checkout's bundle.
        rm -rf "${app}"
        ditto "$bundle" "${app}"
        sign_app

        # One registered bundle. The intermediate is wiped and rebuilt every
        # time, so it is not a cache; left on disk it is a second Mux.app
        # LaunchServices can pick by name over /Applications.
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
