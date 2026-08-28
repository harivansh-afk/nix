# Hermes Desktop on the mac, as a client of the backend on spark.
#
# Nous publishes no prebuilt desktop app: the dmg on their site is a Tauri
# stub that runs install.sh (a local CLI + desktop install), so it cannot act
# as a remote-only client. The Electron app is built here from upstream's own
# nix package against the `minimal` agent, which carries none of the ML chain
# (torch, onnxruntime, faster-whisper) that `full` pulls in.
#
# The backend on spark binds a tailnet name, which engages upstream's auth
# gate. On hermes 0.20.x the env-var route (HERMES_DESKTOP_REMOTE_URL +
# _TOKEN) authenticates with the session token, and the backend honours that
# token on loopback binds only, so those variables cannot be used here. The
# remote is set once in the app instead: Settings -> Gateways -> Remote
# gateway -> URL `http://spark-ix.tail368802.ts.net:9119`, then Sign in with
# the credentials from secrets/hosts/spark/hermes-dashboard.env.
{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  desktop = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.hermesDesktop;

  plist = pkgs.writeText "hermes-desktop-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>hermes-desktop</string>
      <key>CFBundleIconFile</key>
      <string>hermes</string>
      <key>CFBundleIdentifier</key>
      <string>sh.harivan.hermes-desktop</string>
      <key>CFBundleName</key>
      <string>Hermes</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleVersion</key>
      <string>${desktop.version or "0"}</string>
      <key>LSMinimumSystemVersion</key>
      <string>12.0</string>
    </dict>
    </plist>
  '';

  shim = pkgs.writeShellScript "hermes-desktop-shim" ''
    exec ${desktop}/bin/hermes-desktop "$@"
  '';

  bundle = pkgs.runCommand "hermes-desktop-bundle" { nativeBuildInputs = [ pkgs.libicns ]; } ''
    contents="$out/Hermes.app/Contents"
    mkdir -p "$contents/MacOS" "$contents/Resources"
    cp ${plist} "$contents/Info.plist"
    cp ${shim} "$contents/MacOS/hermes-desktop"
    chmod 0755 "$contents/MacOS/hermes-desktop"
    png2icns "$contents/Resources/hermes.icns" \
      ${desktop}/share/icons/hicolor/1024x1024/apps/hermes.png >/dev/null
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    rm -rf /Applications/Hermes.app
    /usr/bin/ditto ${bundle}/Hermes.app /Applications/Hermes.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Hermes.app >/dev/null 2>&1 || true
    # The earlier launchd agent leaked these into the GUI session.
    /bin/launchctl asuser "$(id -u rathi)" /bin/launchctl unsetenv HERMES_DESKTOP_REMOTE_URL 2>/dev/null || true
    /bin/launchctl asuser "$(id -u rathi)" /bin/launchctl unsetenv HERMES_DESKTOP_REMOTE_TOKEN 2>/dev/null || true
  '';
}
