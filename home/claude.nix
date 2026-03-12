{...}: {
  home.file.".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
  home.file.".claude/commands" = {
    source = ../config/claude/commands;
    recursive = true;
  };
  home.file.".claude/settings.json".source = ../config/claude/settings.json;
  home.file.".claude/settings.local.json".source = ../config/claude/settings.local.json;
  home.file.".claude/statusline.sh" = {
    source = ../config/claude/statusline.sh;
    executable = true;
  };
}
