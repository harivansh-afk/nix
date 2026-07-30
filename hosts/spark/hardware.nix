{ lib, ... }:
{
  hardware.dgx-spark = {
    enable = true;
    useNvidiaKernel = true;
  };

  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;

  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              extraFormatArgs = [
                "--pbkdf"
                "argon2id"
                "--type"
                "luks2"
              ];
              settings.crypttabExtraOpts = [ "fido2-device=auto" ];
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "errors=remount-ro"
                  "nodev"
                ];
              };
            };
          };
        };
      };
    };
  };

}
