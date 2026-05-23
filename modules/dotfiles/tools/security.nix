{ config, ... }:
{
  activationLines = ''
    if [ -d "${config.homeDirectory}/.ssh" ]; then
      chmod 700 "${config.homeDirectory}/.ssh"
      for f in "${config.homeDirectory}/.ssh/"*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old)
            chmod 644 "$f" ;;
          *)
            chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d "${config.homeDirectory}/.gnupg" ]; then
      find "${config.homeDirectory}/.gnupg" -type d -exec chmod 700 {} +
      find "${config.homeDirectory}/.gnupg" -type f -exec chmod 600 {} +
    fi
  '';
}
