# DeskPad (the spark-display virtual screen) from pinned source: only main
# has the 3440x1440@60 mode. Voiceink-pattern activation build (system
# Xcode, skip without it), keyed on the src rev plus the patch.
#
# deskpad-no-preview.patch strips the preview window's CGDisplayStream,
# DeskPad's only capture call: no Screen Recording grant needed, and
# macOS 26's recurring legacy-capture nag (it re-fires on every relaunch,
# and the supervisor relaunches DeskPad per cast) never appears. Sunshine
# holds its own grant and does the real capture. The stable-signing scheme
# stays: it keeps LaunchServices and any future TCC grant pinned across
# rebuilds.
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  src = inputs.deskpad-src;
  patch = ./deskpad-no-preview.patch;
  rev =
    (src.rev or src.narHash or "unknown")
    + "-"
    + builtins.substring 0 12 (builtins.hashFile "sha256" patch);
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
        security delete-keychain "${keychain}" 2>/dev/null || true # self-heals into a fresh identity
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

      # capture-then-match, never `| grep -q` (SIGPIPE+pipefail, see voiceink.nix)
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
    patch -d "${build}/src" -p1 <"${patch}"
    xcodebuild -project "${build}/src/DeskPad.xcodeproj" -scheme DeskPad \
      -configuration Release -derivedDataPath "${build}/dd" \
      CODE_SIGN_IDENTITY=- build >/dev/null

    rm -rf "${app}"
    ditto "${build}/dd/Build/Products/Release/DeskPad.app" "${app}"
    sign_app

    # unregister before delete or `open -a DeskPad` resolves the stale entry
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
