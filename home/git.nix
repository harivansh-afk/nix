{ pkgs, theme, ... }:
let
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token.env ]; then
      echo "username=harivansh-afk"
      echo "password=$(cat /run/secrets/forgejo-token.env)"
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
      ".claude/"
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

      delta = {
        "syntax-theme" = theme.deltaTheme theme.defaultMode;
        "hunk-header-style" = "omit";
        "minus-style" = ''syntax "#3c1f1e"'';
        "minus-emph-style" = ''syntax "#72261d"'';
        "plus-style" = ''syntax "#1d2c1d"'';
        "plus-emph-style" = ''syntax "#2b4a2b"'';
      };

      push.autoSetupRemote = true;

      "credential \"https://git.harivan.sh\"" = {
        helper = "!${forgejoCredentialHelper}";
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
