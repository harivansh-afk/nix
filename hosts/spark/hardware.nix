{ ... }:
{
  # Everything DGX Spark-specific (NVIDIA kernel, drivers, podman + CDI,
  # fwupd, Flox CUDA substituter, dashboard on :11000) comes from the
  # upstream module imported in flake/nixos.nix.
  hardware.dgx-spark = {
    enable = true;
    useNvidiaKernel = true; # upstream default; Ethernet only works with this.
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # The real hardware-configuration.nix (filesystem UUIDs, initrd modules,
  # CPU microcode) is generated on-device during `nixos-anywhere` with
  # `--generate-hardware-config nixos-generate-config
  # hosts/spark/hardware-configuration.nix`. After the first install, commit
  # that file and add it to `imports` above.
}
