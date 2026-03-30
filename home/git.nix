{...}: {
  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = "openpgp";

    settings = {
      user = {
        name = "Harivansh Rathi";
        email = "rathiharivansh@gmail.com";
      };

      advice.detachedHead = false;

      core = {
        pager = "diff-so-fancy | less --tabs=4 -RFX";
        editor = "nvim";
      };

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
        "syntax-theme" = "gruvbox-dark";
        "hunk-header-style" = "omit";
        "minus-style" = ''syntax "#3c1f1e"'';
        "minus-emph-style" = ''syntax "#72261d"'';
        "plus-style" = ''syntax "#1d2c1d"'';
        "plus-emph-style" = ''syntax "#2b4a2b"'';
      };

      push.autoSetupRemote = true;

      "diff-so-fancy" = {
        markEmptyLines = true;
        stripLeadingSymbols = true;
        useUnicodeRuler = true;
      };
    };
  };
}
