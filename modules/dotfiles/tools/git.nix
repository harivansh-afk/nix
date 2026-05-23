{
  config,
  pkgs,
  lib,
  theme,
  ...
}:
let
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token.env ]; then
      echo "username=harivansh-afk"
      echo "password=$(cat /run/secrets/forgejo-token.env)"
    fi
  '';

  ignoresContent = ''
    *.swp
    *.swo
    *~
    .DS_Store
    Thumbs.db
    .env
    .env.local
    .env.*.local
    .vscode/
    .idea/
    .claude/
    CLAUDE.md
    node_modules/
    __pycache__/
    *.pyc
    venv/
    .venv/
    build/
    dist/
    out/
    target/
    result
    result-*
    .direnv/
  '';

  renderValue =
    v:
    if v == true then
      "true"
    else if v == false then
      "false"
    else
      toString v;

  renderOpt =
    k: v:
    if builtins.isList v then
      lib.concatMapStringsSep "\n" (item: "\t${k} = ${renderValue item}") v
    else
      "\t${k} = ${renderValue v}";

  renderSection =
    name: opts: "[${name}]\n" + lib.concatStringsSep "\n" (lib.mapAttrsToList renderOpt opts);

  renderGitConfig =
    sections: lib.concatStringsSep "\n\n" (lib.mapAttrsToList renderSection sections) + "\n";

  gitSections = {
    user = {
      name = "Harivansh Rathi";
      email = "rathiharivansh@gmail.com";
      signingKey = "~/.ssh/id_ed25519.pub";
    };
    commit.gpgsign = true;
    gpg.format = "ssh";

    advice.detachedHead = false;

    core = {
      pager = "diff-so-fancy | less --tabs=4 -RFX";
      editor = "nvim";
      fsmonitor = true;
      excludesFile = "${config.xdg.configHome}/git/ignore";
    };

    feature.manyFiles = true;
    interactive.diffFilter = "diff-so-fancy --patch";

    color.ui = true;
    "color \"diff-highlight\"" = {
      oldNormal = "red bold";
      oldHighlight = "red bold 52";
      newNormal = "green bold";
      newHighlight = "green bold 22";
    };
    "color \"diff\"" = {
      meta = 11;
      frag = "magenta bold";
      func = "146 bold";
      commit = "yellow bold";
      old = "red bold";
      new = "green bold";
      whitespace = "red reverse";
    };

    "delta \"cozybox-dark\"" = theme.deltaTheme "dark";
    "delta \"cozybox-light\"" = theme.deltaTheme "light";

    push.autoSetupRemote = true;

    "credential \"https://git.harivan.sh\"" = {
      helper = "!${forgejoCredentialHelper}";
      username = "harivansh-afk";
    };

    # gh credential helper (was programs.gh.gitCredentialHelper.enable)
    "credential \"https://github.com\"".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    "credential \"https://gist.github.com\"".helper = "!${pkgs.gh}/bin/gh auth git-credential";

    "diff-so-fancy" = {
      markEmptyLines = true;
      stripLeadingSymbols = true;
      useUnicodeRuler = true;
    };

    # git-lfs filters
    "filter \"lfs\"" = {
      smudge = "git-lfs smudge -- %f";
      clean = "git-lfs clean -- %f";
      process = "git-lfs filter-process";
      required = true;
    };

    # theme include
    include.path = theme.paths.gitThemeCurrentFile;
  };
in
{
  packages = [
    pkgs.git
    pkgs.git-lfs
    pkgs.diff-so-fancy
  ];

  files.".config/git/config".text = renderGitConfig gitSections;
  files.".config/git/ignore".text = ignoresContent;
}
