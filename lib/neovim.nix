{
  lib,
  pkgs,
  curated ? false,
  configDir ? null,
  extraPackages ? [ ],
}:
let
  sources = builtins.fromJSON (builtins.readFile ../dots/nvim/pack-sources.json);

  plugins = lib.mapAttrs (
    name: source:
    pkgs.vimUtils.buildVimPlugin {
      pname = name;
      version = source.rev;
      src = pkgs.fetchgit { inherit (source) url rev hash; };
      doCheck = false;
    }
  ) sources;

  parserNames = [
    "bash"
    "css"
    "diff"
    "eex"
    "elixir"
    "git_rebase"
    "gitcommit"
    "go"
    "heex"
    "html"
    "javascript"
    "json"
    "markdown"
    "markdown_inline"
    "nix"
    "python"
    "regex"
    "rust"
    "toml"
    "tsx"
    "typescript"
    "yaml"
  ];

  grammarSet = pkgs.vimPlugins.nvim-treesitter-parsers;

  sharedQueryNames = [
    "ecma"
    "html_tags"
    "jsx"
  ];

  sharedQueries = pkgs.runCommand "vimplugin-nvim-treesitter-queries-shared" { } ''
    mkdir -p "$out/queries"
    for name in ${lib.escapeShellArgs sharedQueryNames}; do
      cp -r "${pkgs.vimPlugins.nvim-treesitter}/runtime/queries/$name" "$out/queries/$name"
    done
  '';

  grammars =
    if curated then
      map (name: grammarSet.${name}) parserNames
    else
      lib.filter lib.isDerivation (builtins.attrValues grammarSet);
  treesitter = pkgs.buildEnv {
    name = "nvim-treesitter-runtime";
    paths = [
      sharedQueries
    ]
    ++ grammars
    ++ lib.filter (q: q != null) (map (g: g.associatedQuery or null) grammars);
    postBuild = ''
      for f in "$out"/queries/*/*.scm; do
        for target in $(sed -n 's/^; *inherits: *//p' "$f" | tr ',' ' '); do
          target=''${target#(}
          target=''${target%)}
          if [ ! -e "$out/queries/$target" ]; then
            echo "$f inherits from missing queries/$target" >&2
            exit 1
          fi
        done
      done
    '';
  };
  runtime = pkgs.runCommand "nvim-runtime" { } ''
    mkdir -p "$out/pack/nix/opt"
    ln -s ${treesitter}/parser "$out/parser"
    ln -s ${treesitter}/queries "$out/queries"
    ln -s ${pkgs.vimPlugins.nvim-treesitter} "$out/pack/nix/opt/nvim-treesitter"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: src: ''
        ln -s ${src} "$out/pack/nix/opt/${name}"
      '') plugins
    )}
  '';
in
pkgs.writeShellApplication {
  name = "nvim";
  runtimeInputs = extraPackages;
  text = ''
    case "''${0##*/}" in
      view) set -- -R "$@" ;;
      vimdiff) set -- -d "$@" ;;
    esac
    ${lib.optionalString (configDir != null) "export NVIM_APPNAME=nvim-portable"}
    exec ${pkgs.neovim}/bin/nvim ${
      lib.escapeShellArgs (
        [
          "--cmd"
          "set packpath=${runtime} | set runtimepath^=${runtime}"
        ]
        ++ lib.optionals (configDir != null) [
          "--cmd"
          "lua vim.opt.rtp:remove({ vim.fn.stdpath('config'), vim.fn.stdpath('config') .. '/after' }); vim.opt.rtp:prepend('${configDir}'); vim.opt.rtp:append('${configDir}/after')"
          "-u"
          "${configDir}/init.lua"
        ]
      )
    } "$@"
  '';
}
