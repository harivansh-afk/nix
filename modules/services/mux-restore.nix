# Respawn mux sessions at boot.
#
# mux already tracks "was live" persistently: every server spawn drops a
# `<slug>.restore` sidecar next to its snapshot in
# ~/.local/state/nvim/mux/sessions/ and `mux stop`/`mux kill` remove it.
# This unit only adds the boot-time trigger: when the user manager starts
# (at boot, via linger), `mux restore` re-ensures every marked project so
# sessions come back with their saved layout without anyone attaching first.
#
# RemainAfterExit keeps the unit (and its cgroup, where the respawned nvim
# servers live) active; stopping the unit therefore stops those servers,
# which is the correct teardown anyway (VimLeavePre saves a fresh snapshot).
_: {
  systemd.user.services.mux-restore = {
    description = "restore mux sessions marked live before shutdown";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionFileIsExecutable = "/etc/profiles/per-user/%u/bin/mux";
      ConditionDirectoryNotEmpty = "%h/.local/state/nvim/mux/sessions";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 300;
      ExecStart = "/etc/profiles/per-user/%u/bin/mux restore";
      Environment = [ "PATH=/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin" ];
    };
  };
}
