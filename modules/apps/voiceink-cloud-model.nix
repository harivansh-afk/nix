{
  lib,
  pkgs,
  username,
  ...
}:
let
  domain = "com.prakashjoshipax.voiceink";
  home = "/Users/${username}";
  model = builtins.toJSON {
    name = "spark-whisper";
    displayName = "Spark Whisper Large v3";
    description = "Whisper Large v3 on Spark";
    apiEndpoint = "https://spark-ix.tail368802.ts.net/v1/audio/transcriptions";
    modelName = "openai/whisper-large-v3";
    isMultilingualModel = true;
    supportedLanguages = {
      auto = "Auto-detect";
      en = "English";
    };
  };
  script = pkgs.writeShellScript "voiceink-cloud-model" ''
    set -euo pipefail
    export HOME="${home}"
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
      ]
    }"

    plist="$HOME/Library/Preferences/${domain}.plist"
    if [ ! -f "$plist" ]; then
      exit 0
    fi

    read_data() {
      local encoded
      if encoded=$(/usr/bin/plutil -extract "$1" raw -o - "$plist" 2>/dev/null); then
        printf '%s' "$encoded" | base64 --decode
      else
        printf '[]'
      fi
    }

    write_data() {
      local hex
      hex=$(printf '%s' "$2" | /usr/bin/xxd -p | tr -d '\n')
      /usr/bin/defaults write ${domain} "$1" -data "$hex"
    }

    models=$(read_data customCloudModels)
    updated_models=$(printf '%s' "$models" | jq -c --argjson replacement '${model}' '
      def target:
        .id == "FBE7D583-0619-4FDC-A66B-C2633E9B2389"
        or .name == "spark-parakeet"
        or .modelName == "nvidia/parakeet-tdt-0.6b-v3";
      if any(.[]; target) then
        map(if target then . + $replacement else . end)
      else
        . + [$replacement + {id: "FBE7D583-0619-4FDC-A66B-C2633E9B2389"}]
      end
    ')
    write_data customCloudModels "$updated_models"

    if /usr/bin/plutil -extract modeConfigurationsV2 raw -o - "$plist" >/dev/null 2>&1; then
      modes=$(read_data modeConfigurationsV2)
      updated_modes=$(printf '%s' "$modes" | jq -c '
        map(
          if .selectedTranscriptionModelName == "spark-parakeet"
          then .selectedTranscriptionModelName = "spark-whisper"
          else .
          end
        )
      ')
      write_data modeConfigurationsV2 "$updated_modes"
    fi
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${script} || echo "warning: VoiceInk cloud model configuration failed" >&2
  '';
}
