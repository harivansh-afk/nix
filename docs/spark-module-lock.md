# Spark kernel module lock commissioning

This change preloads Spark's declared runtime modules and permanently disables further kernel module loading after udev settles. The lock resets only at reboot.

The lock is the practical boundary while NVIDIA's out-of-tree GPU modules remain unsigned. Signature enforcement and Secure Boot lockdown cannot activate until every NVIDIA module is signed by a key trusted by the running kernel.

## Acceptance gate

Boot the candidate with a local console and the previous generation available. Before approving the PR, verify:

1. `sysctl kernel.modules_disabled` returns `1`.
2. `nvidia`, `nvidia_drm`, `nvidia_modeset`, and `nvidia_uvm` are loaded. `nvidia_peermem` is deliberately absent: it needs MOFED's PeerDirect API, which this upstream-derived kernel does not carry, so its init returns EINVAL. GPUDirect RDMA on this driver uses the dma-buf path instead.
3. CUDA, inference, ConnectX-7 Ethernet, RDMA, and GPUDirect pass.
4. Wi-Fi, Tailscale, Podman bridge networking, Forgejo builds, and zram pass.
5. Required filesystems and trusted peripherals work without a late `modprobe`.
6. `journalctl -b -k` contains no failed module requests after the lock activates.

Any missing module must be added to `boot.kernelModules` at its owning feature. Do not add a service that reopens module loading or silently ignores a failed `modprobe`.

## Signature-enforcement blocker

The running NVIDIA modules have no signer and taint the kernel as out-of-tree and unsigned. A signing design must sign in-tree and NVIDIA modules after their final transformation, then load the certificate into the kernel trust chain. The private signing key must remain outside the Nix store and outside Spark.

## References

- [Linux kernel module signing](https://docs.kernel.org/admin-guide/module-signing.html)
- [Linux kernel self-protection](https://docs.kernel.org/security/self-protection.html)
- [NVIDIA kernel module verification](https://docs.nvidia.com/igx/user-guide/latest/SW/security/kernel-module-verification.html)
