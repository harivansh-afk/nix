# t3code: the T3 Code server on spark, so the desktop app (macbook) / mobile
# app can run agents here.
#
# The desktop app's "SSH launch" remote flow ssh-es in and, when no server is
# already running, tries `npx --yes t3@<version>`: that dies on NixOS because
# node-pty has no aarch64 prebuild and node-gyp finds no toolchain in the
# non-interactive shell (observed 2026-08-19: "npm error process terminated"
# after the launcher's ready timeout). So the server is the nixpkgs `t3code`
# package instead (its `t3` CLI; node-pty prebuilt in the store), pinned from
# a dedicated nixpkgs input because the main pin lags upstream releases.
#
# It runs as a persistent systemd user service bound to loopback. The SSH
# launcher reads ~/.t3/userdata/server-runtime.json, finds this server ready
# and tunnels to it as an "external" server (packages/ssh/src/tunnel.ts
# REMOTE_LAUNCH_SCRIPT), so connecting from the desktop is just
# Settings -> Connections -> Add environment -> SSH -> rathi@spark. Loopback
# + the ssh tunnel is the whole exposure; nothing is opened on the tailnet.
#
# Provider binaries are whatever this user has on PATH: claude from
# ~/.local/bin and codex from ~/.local/share/npm/bin (both installer-managed
# so their own self-updates keep them latest, and already logged in with the
# user's subscriptions). The nixpkgs wrapper's enableCodex default would
# prefix its own pinned codex ahead of that, so it is turned off.
{ inputs, pkgs, ... }:
let
  t3code = inputs.nixpkgs-t3code.legacyPackages.${pkgs.stdenv.hostPlatform.system}.t3code.override {
    enableCodex = false;
  };
in
{
  environment.systemPackages = [ t3code ];

  # sshd on spark has AllowTcpForwarding off globally (hosts/spark/users.nix);
  # the desktop launcher is exactly a `ssh -L <local>:127.0.0.1:3773`, so
  # rathi gets LOCAL forwarding back, pinned to this one loopback port - the
  # narrowest thing that makes the tunnel work. Match blocks must trail the
  # main config, which is what extraConfig is.
  services.openssh.extraConfig = ''
    Match User rathi
      AllowTcpForwarding local
      PermitOpen 127.0.0.1:3773
  '';

  systemd.user.services.t3code = {
    description = "T3 Code server (loopback; reached over the desktop app's ssh tunnel)";
    wantedBy = [ "default.target" ];
    after = [ "network.target" ];
    # systemd.user.services is global to every user manager on the box. Keep
    # this server pinned to rathi so another user cannot race it for
    # 127.0.0.1:3773.
    unitConfig.ConditionUser = "rathi";
    serviceConfig = {
      ExecStart = "${t3code}/bin/t3 serve --host 127.0.0.1 --port 3773 --base-dir %h/.t3";
      Restart = "on-failure";
      RestartSec = 3;
      Environment = [
        "T3CODE_NO_BROWSER=1"
        "PATH=%h/.local/bin:%h/.local/share/npm/bin:/etc/profiles/per-user/%u/bin:/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
}
