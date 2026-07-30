# Spark encrypted reinstall

This disk layout erases `/dev/nvme0n1`. It replaces plaintext ext4 and raw swap with a LUKS2 root filesystem, a 2 GiB ESP, and zram-only swap. It cannot be activated by `nixos-rebuild switch`.

Full-disk encryption protects powered-off storage. It does not protect plaintext or keys after the running kernel unlocks the volume.

## Required hardware and recovery material

- Two FIDO2 authenticators with `hmac-secret`, PIN, user presence, and onboard user verification
- One generated LUKS recovery key stored offline
- One LUKS header backup stored separately from the recovery key
- Tested NVIDIA recovery media
- A local keyboard and display
- A backup restored and verified before erasure

Do not create a TPM-only unlock slot. Separate TPM and FIDO2 LUKS slots are alternative unlock methods, so the weaker slot becomes the physical-security boundary.

## Installation

1. Boot trusted recovery media and verify its hash.
2. Restore the Secure Boot keys needed to boot the installer, or perform the install with Secure Boot temporarily disabled under physical supervision.
3. Run the repository's Spark installer. Disko prompts for the initial LUKS passphrase.
4. Boot the signed installed system with the initial passphrase.
5. Enroll the operational FIDO2 token:

   ```sh
   sudo systemd-cryptenroll \
     --fido2-device=auto \
     --fido2-with-client-pin=yes \
     --fido2-with-user-presence=yes \
     --fido2-with-user-verification=yes \
     /dev/disk/by-partlabel/disk-main-root
   ```

6. Repeat enrollment with the spare token.
7. Generate and record a recovery key with `systemd-cryptenroll --recovery-key`.
8. Back up the LUKS header with `cryptsetup luksHeaderBackup`.
9. Remove the temporary installation passphrase only after both tokens and the recovery key unlock a cold boot.

Never store a token secret, passphrase, recovery key, or header backup in Git, the Nix store, the ESP, or the encrypted disk it recovers.

## Acceptance gate

1. `cryptsetup luksDump` reports LUKS2 with Argon2id.
2. `/` resolves through `/dev/mapper/cryptroot`.
3. `swapon --show` reports zram and no raw disk partition.
4. Each FIDO2 token independently unlocks a cold boot with PIN, presence, and user verification.
5. The offline recovery key unlocks from recovery media.
6. A restored header backup unlocks a disposable copy of the volume metadata.
7. Suspend, hibernate, hybrid sleep, and suspend-then-hibernate remain unavailable.
8. A signed previous generation remains selectable.

## References

- [NixOS FIDO2 encrypted-root configuration](https://nixos.org/manual/nixos/stable/)
- [systemd-cryptenroll](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html)
- [cryptsetup LUKS format](https://man7.org/linux/man-pages/man8/cryptsetup-luksFormat.8.html)
- [NIST SP 800-111](https://csrc.nist.gov/pubs/sp/800/111/final)
