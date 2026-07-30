# Spark final security commissioning

This profile closes firmware-variable writes, measures the signed UKI and Secure Boot policy into TPM PCRs 4 and 7, removes Wi-Fi provisioning, and rejects every USB device after the encrypted root mounts.

Do not merge until wired management, FIDO2 disk unlock, verified boot, and the recovery path have passed. The empty USBGuard allowlist is intentional. Add a device only after recording its port, interfaces, vendor and product IDs, serial, and descriptor hash. USB descriptors are spoofable, so an allowlist reduces opportunistic access but does not authenticate hardware.

## Remaining Secure Boot blocker

Secure Boot enforcement remains blocked until the NVIDIA GPU modules are signed outside the Nix store with a certificate trusted by the kernel. Enabling firmware enforcement before that work will prevent the NVIDIA modules from loading.

The signing owner must provide:

- An offline token, HSM, or isolated signing service
- An OpenSSL provider usable by `ukify` or `systemd-sbsign`
- The public signing certificate
- A recovery signer and revocation procedure
- A build boundary that signs in-tree and NVIDIA modules after their final transformation

Do not place the private key in a Nix derivation, `/var/lib/sbctl` on Spark, Git, or CI plaintext.

## Physical ceremony

1. Connect and test wired Ethernet, Tailscale, SSH, and Mosh.
2. Rotate the Wi-Fi PSK because its old encrypted secret remains recoverable from repository history by prior recipients.
3. Disable Wireless LAN and Bluetooth in UEFI.
4. Disable the UEFI network stack, PXE, and HTTP boot.
5. Set an administrator password and runtime-variable password protection.
6. Enable the discrete TPM and verify firmware revision and event-log access.
7. Set the signed internal UKI first and new OS boot entries to `Place Last`.
8. Record firmware versions, Secure Boot databases, TPM endorsement identity, installed PCI devices, and chassis serial.
9. Apply numbered tamper seals and record their identifiers outside Spark.
10. Use physical port blockers on unused USB-C ports.

NVIDIA documents no chassis intrusion switch, SPI write-protect control, or rollback control for P4242. Nix cannot claim those protections.

## Acceptance gate

1. `systemd-pcrlock is-supported` reports `yes`.
2. PCR 4 changes when the signed UKI changes and PCR 7 reflects the expected Secure Boot policy.
3. `boot.loader.efi.canTouchEfiVariables` evaluates to false and unattended boot-entry changes fail.
4. The operational and spare FIDO2 tokens each unlock the initrd before USBGuard starts.
5. After root mounts, USBGuard rejects every unlisted device, including the FIDO token and keyboard.
6. No Wi-Fi profile or credential is present, and the radio is disabled in UEFI.
7. Firmware capsule updates pass an attended maintenance drill, including policy regeneration and recovery.
8. An independently stored recovery key, LUKS header, signed generation, and NVIDIA recovery image restore the machine.

## References

- [NVIDIA DGX Spark hardware](https://docs.nvidia.com/dgx/dgx-spark/hardware.html)
- [NVIDIA UEFI security settings](https://docs.nvidia.com/dgx/dgx-spark-uefi/security-tab.html)
- [NVIDIA UEFI advanced settings](https://docs.nvidia.com/dgx/dgx-spark-uefi/advanced-tab.html)
- [Linux USB authorization](https://docs.kernel.org/usb/authorization.html)
- [USBGuard rule language](https://usbguard.github.io/documentation/rule-language)
- [systemd-pcrlock](https://www.freedesktop.org/software/systemd/man/latest/systemd-pcrlock.html)
