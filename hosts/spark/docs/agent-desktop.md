# Agent desktop

Spark runs a persistent Sway Wayland session as rathi, with Chromium and Foot.
The 1600x1000 virtual output renders actual GUI windows without occupying HDMI
or changing nap. Software compositing avoids competing for the NVIDIA display.
Chromium is used because this flake's Google Chrome package is x86_64-only on Linux.

After merging and deploying, `systemctl --user status agent-desktop` checks the
session. User lingering starts it at boot. Stop or restart it with
`systemctl --user stop agent-desktop` / `systemctl --user restart agent-desktop`.
Its apps run with rathi's account access.

## View from the Mac

Keep this SSH tunnel open:

```sh
ssh -N -L 45931:127.0.0.1:45931 spark
```

Connect a VNC viewer to `127.0.0.1:45931` (on macOS,
`open vnc://127.0.0.1:45931`). WayVNC listens only on Spark's loopback; SSH
authenticates and encrypts remote access. Local processes can access the VNC port.
Super+Return opens a terminal, Super+b opens Chromium, Super+f toggles fullscreen.

## Agent control on Spark

Run as rathi, including from an SSH shell. No harness hooks or MCP are required:

```sh
agent-desktop screenshot /tmp/desktop.png
agent-desktop move 1100 400
agent-desktop click
agent-desktop type 'hello world'
agent-desktop key -M ctrl -k l -m ctrl
agent-desktop type 'https://example.com'
agent-desktop key -k Return
agent-desktop exec agent-browser https://example.com
agent-desktop exec foot
```

Screenshots use output pixel coordinates. `key` accepts wtype arguments;
`click` optionally accepts `button1`, `button2`, or `button3`. An agent with shell
and image-viewing tools can use these commands for the screenshot/action loop.

## Dia migration

Browser data stays outside Git and the Nix store, in
`~/.local/share/agent-desktop/chromium`. Dia's Mac profile was located at
`~/Library/Application Support/Dia/User Data/Default`.

Do not copy the whole Mac profile over the Linux profile: encrypted passwords
and cookies depend on the Mac's Keychain, and extensions/settings may be
platform-specific. Bookmarks can be transferred separately. With the desktop
stopped, back up the target `Default/Bookmarks` if present, then copy Dia's
`Default/Bookmarks` there over SSH and restart the desktop.

For passwords, use Dia's password-manager settings to export a CSV on the Mac
(try `chrome://password-manager/settings`). Complete any macOS authentication
prompt locally. Transfer the export over SSH into a private directory on Spark,
then import it through Chromium's `chrome://password-manager/settings`. Delete
the plaintext export from both machines after checking the import. This is a
separate interactive migration step; the PR does not contain or import passwords.
Cookies, passkeys and active logins are not transferred by a password CSV;
sign in again where needed. If passwords live in iCloud or a password-manager
extension instead, export/import through that provider.

Chromium requests GNOME's Secret Service for password encryption. Create and
unlock the keyring before importing passwords. Because this desktop starts via
user lingering rather than a password login, the keyring may require unlocking
after reboot. Unlock it through a desktop keyring prompt. Keep the password out
of command arguments, shell history and agent transcripts.

References: [WayVNC headless setup](https://github.com/any1/wayvnc/blob/master/FAQ.md),
[Chromium Linux password storage](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/linux/password_storage.md).
