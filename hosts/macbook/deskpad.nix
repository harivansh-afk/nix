# DeskPad (the spark-display virtual screen), built from pinned source into
# /Applications. The released binary and its cask stop at 16:9/16:10 modes;
# the ultrawide modes (3440x1440@60 for spark's monitor) exist only on main
# (DeskPad/Frontend/Screen/ScreenViewController.swift), so like VoiceInk this
# is an as-user activation build against the system Xcode, keyed on the
# locked `deskpad-src` rev and skipped (non-fatally) when Xcode is absent.
#
# Same signing rationale as voiceink.nix, compressed: TCC grants pin the
# app's designated requirement, and an ad-hoc signature pins the exact
# cdhash, so every rebuild would orphan DeskPad's Screen Recording grant
# (without it the preview window renders blank - the stream itself is
# unaffected since Sunshine holds its own grant, but a blank preview reads
# as breakage). A machine-local self-signed identity in a dedicated keychain
# makes the requirement identifier+leaf, stable across rebuilds: the grant
# is made once and survives.
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  src = inputs.deskpad-src;
  rev = src.rev or src.narHash or "unknown";
  home = "/Users/${username}";
  build = "${home}/Library/Caches/deskpad-build";
  app = "/Applications/DeskPad.app";
  identity = "DeskPad Local Signing";
  keychain = "${home}/Library/Keychains/deskpad-signing.keychain-db";
  keychainPass = "${home}/Library/Keychains/deskpad-signing.pass";
  lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

  script = pkgs.writeShellScript "deskpad-build" ''
    set -euo pipefail
    export HOME="${home}"
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${lib.makeBinPath [ pkgs.openssl ]}"

    ensure_identity() {
      if [ ! -f "${keychainPass}" ] || [ ! -f "${keychain}" ]; then
        security delete-keychain "${keychain}" 2>/dev/null || true
        rm -f "${keychain}" "${keychainPass}"
        (umask 077 && openssl rand -hex 32 >"${keychainPass}")
        security create-keychain -p "$(cat "${keychainPass}")" "${keychain}"
        security set-keychain-settings "${keychain}"
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

      # No `cmd | grep -q` here for the same SIGPIPE+pipefail reason as
      # voiceink.nix: capture, then pattern-match.
      if [[ "$(security list-keychains -d user)" != *"deskpad-signing.keychain-db"* ]]; then
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
      security unlock-keychain -p "$(cat "${keychainPass}")" "${keychain}"
      codesign --force --deep --sign "${identity}" --keychain "${keychain}" "${app}"
      xattr -cr "${app}"
    }

    built_ok() {
      [ -d "${app}" ] || return 1
      [ "$(cat "${build}/.rev" 2>/dev/null)" = "${rev}" ] || return 1
    }
    signed_ok() {
      [[ "$(codesign -dvv "${app}" 2>&1)" == *"Authority=${identity}"* ]]
    }

    if built_ok && signed_ok; then exit 0; fi
    ensure_identity
    if built_ok; then
      sign_app
      echo "DeskPad: re-signed with stable identity"
      exit 0
    fi
    command -v xcodebuild >/dev/null || { echo "DeskPad: Xcode missing, skipping" >&2; exit 0; }

    echo "DeskPad: building ${rev} from source..."
    rm -rf "${build}/src" && mkdir -p "${build}/src"
    cp -R "${src}/." "${build}/src/" && chmod -R u+w "${build}/src"
    xcodebuild -project "${build}/src/DeskPad.xcodeproj" -scheme DeskPad \
      -configuration Release -derivedDataPath "${build}/dd" \
      CODE_SIGN_IDENTITY=- build >/dev/null

    rm -rf "${app}"
    ditto "${build}/dd/Build/Products/Release/DeskPad.app" "${app}"
    sign_app

    # Unregister the build-tree bundle before deleting it, or `open -a
    # DeskPad` can resolve to the stale LaunchServices entry (bit us live:
    # "Unable to find application named 'DeskPad'" right after an install).
    ${lsregister} -u "${build}/dd/Build/Products/Release/DeskPad.app" >/dev/null 2>&1 || true
    rm -rf "${build}/src" "${build}/dd"
    ${lsregister} -f "${app}" >/dev/null 2>&1 || true

    printf '%s' "${rev}" >"${build}/.rev"
    echo "DeskPad: installed ${rev}"
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${script} || echo "warning: DeskPad build failed" >&2
  '';
}
