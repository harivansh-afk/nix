{ ... }:
{
  # Per-user cgroup caps for non-trusted users on spark.
  #
  # systemd places each login session in user-<UID>.slice; setting
  # MemoryMax there means the kernel OOM-kills processes in that
  # user's tree the moment they exceed it. CPUQuota is across all
  # cores (100% = 1 full core, 400% = 4 cores).
  #
  # GPU access is gated separately by modules/security/gpu-access.nix.
  # These caps are a defense-in-depth backstop against CPU-only
  # runaways (e.g. CPU inference, fork bombs, runaway builds) and
  # against accidental memory growth in long-running user services.
  #
  # rathi (UID 1000) is the host owner and is intentionally uncapped.

  # advait (UID 1002): dev account, no large workloads expected.
  systemd.slices."user-1002".sliceConfig = {
    MemoryHigh = "12G";
    MemoryMax = "16G";
    CPUQuota = "400%";
  };

  # barrett (UID 1001): runs four forgejo CI runners (one job each),
  # each can build a non-trivial Nix derivation. Give him enough
  # headroom for parallel CI without letting it eat the whole box.
  systemd.slices."user-1001".sliceConfig = {
    MemoryHigh = "24G";
    MemoryMax = "32G";
    CPUQuota = "800%";
  };
}
