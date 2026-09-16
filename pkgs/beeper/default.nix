{
  lib,
  fetchurl,
  runCommand,
  squashfsTools,
  asar,
  appimageTools,
  makeWrapper,
}:
let
  pname = "beeper";
  version = "4.3.113";
  src = fetchurl {
    url = "https://beeper-desktop.download.beeper.com/builds/Beeper-${version}-arm64.AppImage";
    hash = "sha256-RJq9adct9i79t03yI9dLhJ9JSfc2YhE0Et3NgYb+o8A=";
  };
  appimageContents =
    runCommand "${pname}-${version}-extracted"
      {
        nativeBuildInputs = [
          squashfsTools
          asar
        ];
      }
      ''
        unsquashfs -d "$out" -o 936456 ${src}
        chmod -R u+w "$out"
        asar extract "$out/resources/app.asar" "$out/resources/app"
        rm "$out/resources/app.asar"
        printf 'export function registerLinuxConfig() {}\n' > "$out"/resources/app/build/main/linux-*.mjs
        substituteInPlace "$out"/resources/app/build/main/main-entry-*.mjs \
          --replace-fail 'return VD.conf.auto_update_disabled??e==="staging"' 'return true'
        printf '#!/usr/bin/env bash\nexec "$APPDIR/beepertexts" "$@"\n' > "$out/AppRun"
      '';
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;
  extraPkgs = pkgs: [ pkgs.libsecret ];
  extraInstallCommands = ''
    install -Dm644 ${appimageContents}/beepertexts.png $out/share/icons/hicolor/512x512/apps/beepertexts.png
    install -Dm644 ${appimageContents}/beepertexts.desktop $out/share/applications/beepertexts.desktop
    substituteInPlace $out/share/applications/beepertexts.desktop --replace-fail "AppRun" "beeper"
    . ${makeWrapper}/nix-support/setup-hook
    wrapProgram $out/bin/beeper --add-flags "--ozone-platform=wayland"
  '';
  passthru = { inherit src appimageContents; };
  meta = {
    description = "Universal chat app";
    homepage = "https://www.beeper.com/";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
    mainProgram = "beeper";
  };
}
