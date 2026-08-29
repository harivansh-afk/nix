# Spark verified boot commissioning

This configuration replaces the ordinary systemd-boot installer with Lanzaboote 1.1.0 and refuses unsigned EFI artifacts. Do not merge it through Spark's automatic deployment workflow until the signing bundle and recovery material exist.

Lanzaboote supports `aarch64-linux` on a best-effort basis and does not test that architecture in upstream CI. Spark must boot two signed generations with Secure Boot disabled before firmware enforcement.

## Key boundary

Use an owner PK, KEK, and db hierarchy. Keep the PK and KEK private keys offline. Preserve the factory dbx and the OEM or Microsoft authorities required by firmware capsules and ConnectX-7 option ROMs during initial enrollment.

Lanzaboote signs with the db private key at `/var/lib/sbctl`. Root on Spark can steal that key and authorize persistent boot malware. This is a staging implementation, not the final root-resistant signer.

The final signer must use `ukify` or `systemd-sbsign` with an OpenSSL provider backed by an offline token, HSM, or isolated signing service. The repository cannot select that provider until its hardware, public certificate, and recovery owner are known.

## Required offline material

- NVIDIA recovery media tested on a spare USB device
- Exported factory PK, KEK, db, and dbx
- Owner PK and KEK private keys
- A copy of the db public certificate
- The UEFI administrator password
- The last known bootable signed generation

None of the private keys or passwords may enter Git, the Nix store, the ESP, or an unencrypted backup.

## Staging gate

1. Create `/var/lib/sbctl` with mode `0700` and provision the owner signing bundle.
2. Leave Secure Boot disabled.
3. Build and install the candidate:

   ```sh
   sudo nixos-rebuild boot --flake .#spark
   ```

4. Confirm every EFI executable in the new generation has the expected db signature.
5. Reboot the signed generation twice and verify GPU, NVMe, Wi-Fi, ConnectX-7, Tailscale, and firmware inventory.
6. Confirm the previous recovery generation is also signed and selectable.

## UEFI ceremony

With local console access:

1. Set a strong UEFI administrator password.
2. Enable `Security Device Support` for the discrete TPM.
3. Export the current Secure Boot databases again.
4. Enroll the owner PK, KEK, and db while retaining required vendor authorities and dbx.
5. Enable Secure Boot and confirm User mode.
6. Enable password protection for runtime UEFI variables.
7. Disable the UEFI network stack, IPv4 and IPv6 PXE, and IPv4 and IPv6 HTTP boot.
8. Set the signed internal UKI first and `New UEFI OS Boot Option Policy` to `Place Last`.
9. Disable Wi-Fi and Bluetooth only after wired management has passed.

After boot, `bootctl status` must report Secure Boot enabled, `/sys/kernel/security/lockdown` must not report `none`, and `systemd-pcrlock is-supported` must report `yes`. A later commissioning PR must set `boot.loader.efi.canTouchEfiVariables = false` after firmware-update staging has been tested.

## References

- [NVIDIA DGX Spark UEFI security settings](https://docs.nvidia.com/dgx/dgx-spark-uefi/security-tab.html)
- [NVIDIA DGX Spark UEFI advanced settings](https://docs.nvidia.com/dgx/dgx-spark-uefi/advanced-tab.html)
- [NVIDIA DGX Spark UEFI boot settings](https://docs.nvidia.com/dgx/dgx-spark-uefi/boot-tab.html)
- [NVIDIA DGX Spark recovery](https://docs.nvidia.com/dgx/dgx-spark/system-recovery.html)
- [Lanzaboote system preparation](https://github.com/nix-community/lanzaboote/blob/v1.1.0/docs/getting-started/prepare-your-system.md)
- [systemd ukify](https://www.freedesktop.org/software/systemd/man/latest/ukify.html)
