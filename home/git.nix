{ pkgs, theme, ... }:
let
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token.env ]; then
      echo "username=harivansh-afk"
      echo "password=$(cat /run/secrets/forgejo-token.env)"
    fi
  '';

  ixForgejoCredentialHelper = pkgs.writeShellScript "git-credential-ix-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-ix.env ]; then
      set -a
      . /run/secrets/forgejo-ix.env
      echo "username=harivansh-afk"
      echo "password=$FORGEJO_IX_TOKEN"
    fi
  '';
in
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    signing = {
      format = "ssh";
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    includes = [
      { path = theme.paths.gitThemeCurrentFile; }
    ];

    ignores = [
      "*.swp"
      "*.swo"
      "*~"
      ".DS_Store"
      "Thumbs.db"
      ".env"
      ".env.local"
      ".env.*.local"
      ".vscode/"
      ".idea/"
      # Track committed .claude content (agents, hooks, settings.json) across all
      # repos; only the per-machine local override stays out of git.
      ".claude/settings.local.json"
      "CLAUDE.md"
      "node_modules/"
      "__pycache__/"
      "*.pyc"
      "venv/"
      ".venv/"
      "build/"
      "dist/"
      "out/"
      "target/"
      "result"
      "result-*"
      ".direnv/"
    ];

    settings = {
      user = {
        name = "Harivansh Rathi";
        email = "rathiharivansh@gmail.com";
      };

      advice.detachedHead = false;

      core = {
        pager = "diff-so-fancy | less --tabs=4 -RFX";
        editor = "nvim";
        fsmonitor = true;
      };

      feature.manyFiles = true;

      interactive.diffFilter = "diff-so-fancy --patch";

      color = {
        ui = true;
        "diff-highlight" = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };
        diff = {
          meta = 11;
          frag = "magenta bold";
          func = "146 bold";
          commit = "yellow bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };
      };

      "delta \"cozybox-dark\"" = theme.deltaTheme "dark";

      "delta \"cozybox-light\"" = theme.deltaTheme "light";

      push.autoSetupRemote = true;

      "credential \"https://git.harivan.sh\"" = {
        helper = "!${forgejoCredentialHelper}";
        username = "harivansh-afk";
      };

      "credential \"https://git.ix.dev\"" = {
        helper = "!${ixForgejoCredentialHelper}";
        username = "harivansh-afk";
      };

      "diff-so-fancy" = {
        markEmptyLines = true;
        stripLeadingSymbols = true;
        useUnicodeRuler = true;
      };
    };
  };
}
