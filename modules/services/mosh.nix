_: {
  programs.mosh.enable = true;

  # mosh-server keeps no model of the real terminal's default colors, so it
  # never answers OSC 10/11/12 color queries. Programs that probe the terminal
  # background that way (Codex's TUI inside tmux) time out and render with no
  # background. This overlay patches mosh-server to answer those queries with
  # the cozybox dark palette (overridable per-host via MOSH_OSC_FG/BG/CURSOR).
  # Only the server side runs the emulator, so this only matters where mosh is
  # the remote host (spark); the patch is harmless on clients.
  nixpkgs.overlays = [
    (_final: prev: {
      mosh = prev.mosh.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./mosh-osc-color.patch ];
      });
    })
  ];
}
