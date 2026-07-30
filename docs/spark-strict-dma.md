# Spark strict DMA commissioning

This change replaces the NVIDIA kernel's default identity DMA domains with translated, strict IOMMU mappings. It must not merge until Spark passes the reboot test below from the candidate generation.

NVIDIA warns that IOMMU translation can reduce GPUDirect performance or hang a workload on Grace systems. A successful boot is insufficient evidence.

## Before reboot

1. Keep a local console and the previous NixOS generation available.
2. Record the baseline:

   ```sh
   readlink -f /sys/kernel/iommu_groups/*/devices/*
   nvidia-smi
   ibv_devinfo
   ```

3. Build the candidate without activating it:

   ```sh
   sudo nixos-rebuild boot --flake .#spark
   ```

## Acceptance gate

After rebooting the candidate, all of these must pass:

1. `/proc/cmdline` contains `iommu.passthrough=0 iommu.strict=1`.
2. Every PCI device under `/sys/kernel/iommu_groups` uses a translated Arm SMMU domain. No ConnectX-7, NVMe, or GPU-adjacent device remains in an identity domain.
3. `nvidia-smi` reports the GPU and the CUDA sample suite completes.
4. ConnectX-7 Ethernet, RDMA, and GPUDirect complete without a kernel warning, timeout, or reset.
5. Forgejo builds, Podman networking, inference, Wi-Fi, and Tailscale pass their normal checks.
6. GPU and network throughput remain within the operator-approved budget compared with the baseline.

If any check fails, select the previous signed generation at boot. Do not disable the IOMMU globally as an emergency workaround.

## References

- [Linux kernel IOMMU parameters](https://docs.kernel.org/admin-guide/kernel-parameters.html)
- [NVIDIA Grace performance tuning: IOMMU and GPUDirect](https://docs.nvidia.com/dccpu/grace-perf-tuning-guide/os-settings.html)
