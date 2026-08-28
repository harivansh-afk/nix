{ config, lib, ... }:
let
  backendUrl = "http://spark-ix.tail368802.ts.net:9119";
  tokenPath = config.sops.secrets."hermes-backend-token".path;
  dmgUrl = "https://hermes-assets.nousresearch.com/Hermes-Setup.dmg";
in
{
  launchd.user.agents.hermes-desktop-env.serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      ''
        /bin/launchctl setenv HERMES_DESKTOP_REMOTE_URL ${backendUrl}
        if [ -r ${tokenPath} ]; then
          /bin/launchctl setenv HERMES_DESKTOP_REMOTE_TOKEN "$(/usr/bin/tr -d '\r\n' < ${tokenPath})"
        fi
      ''
    ];
    RunAtLoad = true;
    KeepAlive = false;
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    if [ ! -d /Applications/Hermes.app ]; then
      echo "Hermes: installing desktop app from ${dmgUrl}"
      hermes_tmp=$(mktemp -d)
      if /usr/bin/curl -fsSL ${dmgUrl} -o "$hermes_tmp/Hermes.dmg" \
        && /usr/bin/hdiutil attach "$hermes_tmp/Hermes.dmg" -nobrowse -quiet -mountpoint "$hermes_tmp/mnt"; then
        app_src=$(/bin/ls -d "$hermes_tmp/mnt/"*.app 2>/dev/null | head -1)
        if [ -n "$app_src" ]; then
          /usr/bin/ditto "$app_src" /Applications/Hermes.app
        else
          echo "warning: Hermes dmg contained no .app" >&2
        fi
        /usr/bin/hdiutil detach "$hermes_tmp/mnt" -quiet || true
      else
        echo "warning: Hermes desktop download failed; retry with the next switch" >&2
      fi
      rm -rf "$hermes_tmp"
    fi
  '';
}
