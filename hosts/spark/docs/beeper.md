# Beeper on Spark

Beeper runs on Spark's existing always-on headless Sway desktop, not on the Mac.
`services/desktop.nix` installs the package and starts the `beeper` user service
only after Sway exports its Wayland environment. The service follows Sway's
lifecycle, is restricted to `rathi`, and restarts if Beeper exits. Quit/disable
Beeper's own launch-at-login option; systemd owns startup. To intentionally stop
it, use `systemctl --user stop beeper` rather than quitting the window.

## Package

The locked nixpkgs Beeper 4.2.892 supports only x86_64 Linux. Until that package
supports ARM64, `pkgs/beeper` pins the official Beeper 4.3.113 ARM64 AppImage by
versioned URL and SHA-256. No flake input is changed. The download is linked from
[Beeper's download page](https://www.beeper.com/download); the ARM64 stable
resolver is:

```
https://api.beeper.com/desktop/download/linux/arm64/stable/com.automattic.beeper.desktop
```

This upstream image lacks the AppImage magic bytes checked by the locked
`appimageTools.extract`. Its SquashFS payload starts at byte `936456`, confirmed
with the image's `--appimage-offset`. The derivation extracts that fixed payload
with `unsquashfs`, without executing the vendor binary during the build, then
uses nixpkgs' FHS wrapper. On updates, resolve the official redirect again,
recompute the fixed hash, verify the payload offset, and review the updater patch
against the new bundled JavaScript. `substituteInPlace --replace-fail` makes a
changed patch target fail the build rather than silently enabling updates.

The package disables upstream self-updates and runtime desktop-file registration;
Nix owns those files. It replaces upstream's AppRun script because that script
silently adds `--no-sandbox` if its namespace probe fails. The replacement launches
Electron directly, retaining its sandbox; unsupported sandbox configurations must
fail rather than weaken security. Native Wayland is explicit because this Sway
session disables Xwayland.

## Manual first run after an approved deployment

This change does not deploy itself. After merging/deploying through the usual
reviewed process, use Spark's existing private remote desktop (see `browser.md`).
A newly deployed unit may need `systemctl --user start beeper` from the existing
Sway session; future Sway starts launch it automatically. Do not restart Sway
just to open Beeper, since that interrupts the other desktop applications.

1. Open Beeper and choose **Continue with Email**. Complete Beeper's sign-in and
   any verification manually. Existing account state remains mutable in the
   user's Beeper profile; it is not part of the Nix store.
2. In Beeper's network settings, connect **Signal, Slack, LinkedIn and X** as
   desired. Complete each network's own login, QR/device linking and 2FA prompts.
   Prefer on-device connections where offered. Verify a real chat in each
   network before treating that connection as usable.
3. **Snapchat is unsupported. iMessage is explicitly out of scope** for this
   Linux setup; do not change the separate iMessage stack. Beeper lists iMessage
   as macOS-only. See the [supported-network list](https://help.beeper.com/en_US/chat-networks/which-chat-networks-can-you-connect-in-beeper).
4. Only after account/network setup, enable Beeper's local Desktop API/MCP in its
   settings and approve the intended client. Follow the current
   [Desktop API](https://developers.beeper.com/desktop-api) and
   [MCP](https://developers.beeper.com/desktop-api/mcp) instructions.
5. The MCP endpoint is `http://localhost:23373/v0/mcp` on Spark. Verify its listener
   with `ss -ltnp '( sport = :23373 )'`: only loopback (`127.0.0.1`/`::1`) is
   acceptable. Keep this port out of Caddy, cloudflared and firewall openings.
   Do not use `0.0.0.0` or publish it over the tailnet.
6. Configure the intended Hermes profile only after authenticated local API
   access works. Store any issued credential through the existing runtime secret
   mechanism, never in this repository, the Nix store or a fabricated SOPS entry.
   This change deliberately does not add a token or a premature Hermes MCP entry.

Beeper must stay running for its local API and on-device connections to work.
Network authentication, history availability, message delivery and MCP client
approval require manual acceptance; a successful package build proves none of
those.

## Verification

From the checkout, build without installing or switching the host:

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in f.nixosConfigurations.spark.pkgs.callPackage ./pkgs/beeper {}'
nix eval --raw .#nixosConfigurations.spark.config.system.build.toplevel.drvPath
nix eval --raw '.#nixosConfigurations.spark.config.systemd.user.units."beeper.service".text'
nix fmt -- --ci --tree-root "$PWD" --walk git
nix flake check
```

Initial runtime smoke testing used a separate headless Sway, private D-Bus session
and temporary HOME/XDG directories, leaving the live desktop and account state
alone. The ARM64 package mapped a native `xdg_shell` Beeper window and displayed
**Continue with Email** with no sandbox-disabling flag. The temporary environment
reported document-portal FUSE/PipeWire warnings; attachment picking, audio,
keyring persistence and authenticated integrations still need first-run testing.
