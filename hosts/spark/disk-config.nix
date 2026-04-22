{ lib, ... }:
{
  # Single NVMe, GPT: 512 MiB ESP + 2 GiB swap + ext4 root.
  # Starting point copied from graham33/nixos-dgx-spark#nixos-anywhere/disk-config.nix.
  # Later hardening options: wrap root in LUKS, move to bcachefs/zfs for
  # snapshots, drop the swap partition in favour of zramSwap.
  disko.devices = {
    disk.main = {
      device = lib.mkDefault "/dev/nvme0n1";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          swap = {
            size = "2G";
            content = {
              type = "swap";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
