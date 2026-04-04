{ lib, ... }:
{
  # Write gcloud config as mutable files (not Nix store symlinks) so that
  # gcloud auth / gws auth can update them at runtime.
  home.activation.gcloudConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -Dm644 /dev/null "$HOME/.config/gcloud/active_config"
    printf 'default' > "$HOME/.config/gcloud/active_config"

    install -Dm644 /dev/null "$HOME/.config/gcloud/configurations/config_default"
    printf '[core]\naccount=rathiharivansh@gmail.com\nproject=hari-gc\n' \
      > "$HOME/.config/gcloud/configurations/config_default"
  '';
}
