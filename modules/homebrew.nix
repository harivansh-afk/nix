{...}: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "uninstall";
    };

    taps = [
      "humanlayer/humanlayer"
      "gromgit/fuse"
      "mutagen-io/mutagen"
    ];

    brews = [
      "bitwarden-cli"
      "gromgit/fuse/sshfs-mac"
      "mutagen-io/mutagen/mutagen"
    ];

    casks = [
      "cap"
      "codex"
      "karabiner-elements"
      "macfuse"
      "rectangle"
      "raycast"
      "riptide-beta"
      "thebrowsercompany-dia"
      "wispr-flow"
    ];
  };
}
