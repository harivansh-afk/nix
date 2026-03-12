{
  config,
  lib,
  ...
}: let
  dotfilesDir = "${config.home.homeDirectory}/dots";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${path}";
in {
  home.activation.ensureDotfilesRepo = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    if [ ! -d "${dotfilesDir}" ]; then
      echo "Expected dotfiles repo at ${dotfilesDir}"
      exit 1
    fi
  '';

  home.file.".aerospace.toml".source = link "aerospace/.aerospace.toml";

  home.file.".zshenv".source = link "zsh/.zshenv";
  home.file.".zshrc".source = link "zsh/.zshrc";

  home.file.".config/nvim".source = link "nvim/.config/nvim";

  home.file.".config/karabiner/karabiner.json".source =
    link "karabiner/.config/karabiner/karabiner.json";

  home.file.".claude/CLAUDE.md".source = link "claude/.claude/CLAUDE.md";
  home.file.".claude/commands".source = link "claude/.claude/commands";
  home.file.".claude/settings.json".source = link "claude/.claude/settings.json";
  home.file.".claude/statusline.sh".source = link "claude/.claude/statusline.sh";

  home.file.".codex/AGENTS.md".source = link "codex/.codex/AGENTS.md";
  home.file.".codex/config.toml".source = link "codex/.codex/config.toml";

  home.file."Library/Application Support/lazygit/config.yml".source =
    link "lazygit/Library/Application Support/lazygit/config.yml";
}
