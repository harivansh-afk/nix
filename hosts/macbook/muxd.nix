# muxd on the macbook: a launchd user agent, the same ownership spark gives
# it under systemd (hosts/spark/services/muxd.nix).
#
# Before this the daemon was whatever process last spawned it. On
# 2026-08-28 that was a `muxd upgrade` run from a Claude pane, and every
# pane since carried the harness's GIT_EDITOR=true, so `git commit` in any
# shell aborted on an empty message. Under launchd the daemon's
# environment is launchd's, the agent comes back if the daemon dies, and a
# muxd bump is a switch (which restarts the agent and drops the panes; the
# mux flake's nix/darwin.nix header explains why launchd cannot do the
# in-place handoff systemd does).
#
# Mux.app still ships its own muxd copy and only spawns one when nothing
# owns the control socket, or upgrades on a protocol mismatch. Rebuilding
# the app from the same mux rev keeps both on one protocol so neither path
# fires. The app's own nix install is not here yet: /Applications/Mux.app
# is a hand copy of the scripts/make-app.sh build.
{
  inputs,
  username,
  ...
}:
let
  home = "/Users/${username}";
  uid = "$(id -u ${username})";
  label = "org.nixos.muxd";
in
{
  imports = [ inputs.mux.darwinModules.muxd ];

  services.muxd = {
    enable = true;
    inherit home;
  };

  # One-time handover: a muxd from before this agent existed still owns
  # /tmp/muxd-<uid>.sock, and the launchd one would exit "already running"
  # on every KeepAlive retry. Kill any muxd launchd does not own, then
  # kick the agent so it takes the socket now instead of at the next retry.
  # Steady state is a no-op: the only muxd is the agent's.
  system.activationScripts.postActivation.text = ''
    muxd_owned="$(launchctl print gui/${uid}/${label} 2>/dev/null | awk '/^\s*pid = /{print $3}')"
    for pid in $(pgrep -x muxd -u ${username} || true); do
      if [ "$pid" != "''${muxd_owned:-}" ]; then
        echo "muxd: killing stray daemon $pid (not the launchd agent)"
        kill "$pid" || true
      fi
    done
    launchctl kickstart gui/${uid}/${label} 2>/dev/null || true
  '';
}
