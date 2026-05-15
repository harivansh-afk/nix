{ ... }:
{
  # Per-user cgroup caps on spark for shared user accounts.
  #
  # systemd places each login session in user-<UID>.slice. Setting
  # MemoryMax there means the kernel OOM-kills processes in that
  # user's tree the moment they exceed it. CPUQuota is across all
  # cores (100% = 1 full core, 800% = 8 cores).
  #
  # rathi (UID 1000) is the host owner and is intentionally uncapped.

  systemd.slices."user-1001".sliceConfig = {
    # barrett
    MemoryHigh = "24G";
    MemoryMax = "32G";
    CPUQuota = "800%";
  };

  systemd.slices."user-1002".sliceConfig = {
    # advait
    MemoryHigh = "24G";
    MemoryMax = "32G";
    CPUQuota = "800%";
  };
}
