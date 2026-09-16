# Beeper on Spark

Beeper runs as `rathi` on Spark's headless Sway desktop. Sway starts the `beeper`
user service after exporting its Wayland environment. Disable Beeper's own
launch-at-login option; systemd owns startup and restarts it on exit. To stop it,
use `systemctl --user stop beeper`.

## Package

The locked nixpkgs package is x86_64-only, so `pkgs/beeper` pins the official
4.3.113 ARM64 AppImage. For updates, resolve the versioned download from:

```
https://api.beeper.com/desktop/download/linux/arm64/stable/com.automattic.beeper.desktop
```

The image lacks the magic bytes required by `appimageTools.extract`, so
`unsquashfs` extracts its payload at byte `936456` (verified with
`--appimage-offset`). On updates, recheck the offset and hash and review the
bundled JavaScript patches; the updater replacement must continue to fail on
a changed target.

Nix owns updates and desktop-file registration. The replacement AppRun preserves
Electron's sandbox instead of upstream's automatic `--no-sandbox` fallback.
Native Wayland is required because this Sway session disables Xwayland.

## First run

After deployment, open Spark's private remote desktop (see `browser.md`). If Sway
is already running, use `systemctl --user start beeper`; no Sway restart is needed.

1. Choose **Continue with Email** and complete sign-in manually.
2. Connect **Signal, Slack, LinkedIn and X** as desired, completing each network's
   login/device linking and 2FA. Verify a real chat in each. **Snapchat is
   unsupported; iMessage is out of scope on Linux.** See the
   [supported networks](https://help.beeper.com/en_US/chat-networks/which-chat-networks-can-you-connect-in-beeper).
3. After account setup, enable the local Desktop API/MCP and approve the intended
   client using the [MCP instructions](https://developers.beeper.com/desktop-api/mcp).
   The endpoint is `http://localhost:23373/v0/mcp`. Check
   `ss -ltnp '( sport = :23373 )'`: only `127.0.0.1`/`::1` is acceptable.
   Do not expose it through Caddy, cloudflared, firewall rules or the tailnet.
4. Configure the intended Hermes profile only after authenticated API access
   works. Keep credentials in runtime secret storage, never the repository or
   Nix store. No credentials or Hermes configuration are provisioned here.

Beeper must stay running for its API and on-device connections. Authenticated
messaging, MCP, attachment picking, audio and keyring persistence need manual
acceptance; the isolated Wayland smoke test only verifies startup.
