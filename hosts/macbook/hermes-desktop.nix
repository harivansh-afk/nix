{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  backendUrl = "http://spark-ix.tail368802.ts.net:9119";
  tokenPath = config.sops.secrets."hermes-backend-token".path;

  desktop = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop.override {
    extraEnv.HERMES_DESKTOP_REMOTE_URL = backendUrl;
    extraRun = [
      ''
        if [ -r ${lib.escapeShellArg tokenPath} ]; then
          HERMES_DESKTOP_REMOTE_TOKEN="$(tr -d '\r\n' < ${lib.escapeShellArg tokenPath})"
          export HERMES_DESKTOP_REMOTE_TOKEN
        else
          echo "hermes-desktop: cannot read the session token at ${tokenPath}" >&2
        fi
      ''
    ];
  };

  plist = pkgs.writeText "hermes-desktop-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>hermes-desktop</string>
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

  bundle = pkgs.runCommand "hermes-desktop-bundle" { } ''
    contents="$out/Hermes.app/Contents"
    mkdir -p "$contents/MacOS" "$contents/Resources"
    cp ${plist} "$contents/Info.plist"
    cp ${shim} "$contents/MacOS/hermes-desktop"
    chmod 0755 "$contents/MacOS/hermes-desktop"
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    rm -rf /Applications/Hermes.app
    /usr/bin/ditto ${bundle}/Hermes.app /Applications/Hermes.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Hermes.app >/dev/null 2>&1 || true
  '';
}
