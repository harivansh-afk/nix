{ ... }:
{
  # Restrict NVIDIA GPU device nodes to members of the `gpu` group.
  #
  # By default the NVIDIA driver creates /dev/nvidia* with mode 0666
  # (world-rw), so every logged-in shell user can issue CUDA calls,
  # load a model into VRAM, and pin host pages via the NVIDIA driver.
  # On a multi-user box this routinely tanks the host: driver-pinned
  # pages do not show up in cgroup accounting and the kernel has no
  # per-user budget for them, so one user's model can starve the rest
  # of the system without tripping any per-user MemoryMax.
  #
  # Gate the device nodes behind a dedicated `gpu` group; only members
  # can talk to the card.

  users.groups.gpu = { };

  services.udev.extraRules = ''
    KERNEL=="nvidia",            MODE="0660", GROUP="gpu"
    KERNEL=="nvidia[0-9]*",      MODE="0660", GROUP="gpu"
    KERNEL=="nvidiactl",         MODE="0660", GROUP="gpu"
    KERNEL=="nvidia-modeset",    MODE="0660", GROUP="gpu"
    KERNEL=="nvidia-uvm",        MODE="0660", GROUP="gpu"
    KERNEL=="nvidia-uvm-tools",  MODE="0660", GROUP="gpu"
  '';

  # Trusted users. Add the host owner; other users are intentionally
  # omitted so they cannot open the GPU device nodes at all.
  users.users.rathi.extraGroups = [ "gpu" ];
}
