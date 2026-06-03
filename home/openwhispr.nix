{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  version = "1.7.2";

  # Signed, notarized arm64 build. Fetched into the nix store (no quarantine
  # xattr), then installed into a stable /Applications path so macOS TCC grants
  # (Accessibility, Microphone, Input Monitoring) survive across rebuilds.
  zip = pkgs.fetchurl {
    url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-arm64-mac.zip";
    hash = "sha256-tl6yg5Q5+40ZXk8ctC4lVy+H8OTomIcYBgqytRVUPGI=";
  };

  # OpenWhispr loads this .env from its userData dir with override = true, so
  # these values win over anything set through the UI. Only on-device settings
  # are read from .env: remote/self-hosted endpoints live in the app's
  # localStorage and cannot be set declaratively, which is why we run Parakeet
  # locally rather than against a remote server.
  #
  #   parakeet-tdt-0.6b-v3      latest, multilingual (set LANGUAGE=en for English)
  #   parakeet-unified-en-0.6b  English-only, slightly higher accuracy
  # PANEL_START_POSITION accepts: bottom-right | center | bottom-left.
  # FLOATING_ICON_AUTO_HIDE=true hides the floating icon when not dictating, so
  # it is not parked on screen all the time.
  envText = ''
    # Managed by nix (home/openwhispr.nix). Edits are overwritten on rebuild.
    LOCAL_TRANSCRIPTION_PROVIDER=parakeet
    PARAKEET_MODEL=parakeet-tdt-0.6b-v3
    LANGUAGE=en
    UI_LANGUAGE=en
    DICTATION_KEY=GLOBE
    ACTIVATION_MODE=push
    FLOATING_ICON_AUTO_HIDE=true
    PANEL_START_POSITION=bottom-left
  '';
  envSrc = pkgs.writeText "openwhispr-env" envText;

  appPath = "/Applications/OpenWhispr.app";
  supportDir = "${config.home.homeDirectory}/Library/Application Support/OpenWhispr";
  stampPath = "${supportDir}/.nix-version";
  envPath = "${supportDir}/.env";
in
lib.mkIf hostConfig.isDarwin {
  home.activation.installOpenWhispr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    support=${lib.escapeShellArg supportDir}
    app=${lib.escapeShellArg appPath}
    stamp=${lib.escapeShellArg stampPath}
    env=${lib.escapeShellArg envPath}

    $DRY_RUN_CMD mkdir -p "$support"

    if [ ! -d "$app" ] || [ "$(cat "$stamp" 2>/dev/null)" != ${lib.escapeShellArg version} ]; then
      $DRY_RUN_CMD rm -rf "$app"
      $DRY_RUN_CMD /usr/bin/ditto -x -k ${zip} /Applications
      $DRY_RUN_CMD printf '%s' ${lib.escapeShellArg version} > "$stamp"
    fi

    # Re-enforce declarative settings on every rebuild (writable copy so the app
    # can still persist its own non-managed state alongside).
    $DRY_RUN_CMD cp ${envSrc} "$env"
    $DRY_RUN_CMD chmod 600 "$env"
  '';
}
