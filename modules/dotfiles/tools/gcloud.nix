{ pkgs, lib, ... }:
{
  activationLines = ''
    ${pkgs.coreutils}/bin/install -Dm644 /dev/null "$HOME/.config/gcloud/active_config"
    printf 'default' > "$HOME/.config/gcloud/active_config"

    ${pkgs.coreutils}/bin/install -Dm644 /dev/null "$HOME/.config/gcloud/configurations/config_default"
    printf '[core]\naccount=rathiharivansh@gmail.com\nproject=hari-gc\n' \
      > "$HOME/.config/gcloud/configurations/config_default"
  '';
}
