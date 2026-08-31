{ lib, pkgs }:
let
  sources = builtins.fromJSON (builtins.readFile ../dots/nvim/pack-sources.json);

  fetchPlugin = _name: source: pkgs.fetchgit { inherit (source) url rev hash; };

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

  mkTreesitterEnv =
    name: grammars:
    pkgs.buildEnv {
      inherit name;
      paths = grammars ++ lib.filter (q: q != null) (map (g: g.associatedQuery or null) grammars);
    };
in
{
  plugins = lib.mapAttrs fetchPlugin sources;
  treesitter = {
    plugin = pkgs.vimPlugins.nvim-treesitter;
    full = mkTreesitterEnv "nvim-treesitter-grammars-full" (
      lib.filter lib.isDerivation (builtins.attrValues grammarSet)
    );
    curated = mkTreesitterEnv "nvim-treesitter-grammars-curated" (
      map (
        name: grammarSet.${name} or (throw "nvim-treesitter-parsers has no grammar ${name}")
      ) parserNames
    );
  };
  lockFile = pkgs.writeText "nvim-pack-lock.json" (
    builtins.toJSON {
      plugins = lib.mapAttrs (_: source: {
        inherit (source) rev;
        src = source.url;
      }) sources;
    }
  );
}
