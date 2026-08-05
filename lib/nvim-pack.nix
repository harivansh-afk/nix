{ lib, pkgs }:
let
  sources = builtins.fromJSON (builtins.readFile ../dots/nvim/pack-sources.json);

  fetchPlugin = _name: source: pkgs.fetchgit { inherit (source) url rev hash; };

  bundledParsers = [
    "c"
    "lua"
    "markdown"
    "markdown_inline"
    "query"
    "vim"
    "vimdoc"
  ];

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
    "nix"
    "python"
    "regex"
    "rust"
    "toml"
    "tsx"
    "typescript"
    "yaml"
  ];

  fetchParser =
    name:
    let
      attr = "tree-sitter-" + lib.replaceStrings [ "_" ] [ "-" ] name;
    in
    pkgs.tree-sitter-grammars.${attr}
      or (throw "nixpkgs has no tree-sitter-grammars.${attr} for parser ${name}");
in
{
  plugins = lib.mapAttrs fetchPlugin sources;
  parsers = lib.genAttrs (lib.subtractLists bundledParsers parserNames) fetchParser;
}
