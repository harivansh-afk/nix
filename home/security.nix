{
  config,
  lib,
  ...
}:
{
  home.activation.secretPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "${config.home.homeDirectory}/.ssh" ]; then
      $DRY_RUN_CMD chmod 700 "${config.home.homeDirectory}/.ssh"
      for f in "${config.home.homeDirectory}/.ssh/"*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old)
            $DRY_RUN_CMD chmod 644 "$f" ;;
          *)
            $DRY_RUN_CMD chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d "${config.home.homeDirectory}/.gnupg" ]; then
      $DRY_RUN_CMD find "${config.home.homeDirectory}/.gnupg" -type d -exec chmod 700 {} +
      $DRY_RUN_CMD find "${config.home.homeDirectory}/.gnupg" -type f -exec chmod 600 {} +
    fi
  '';
}
