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

  # Query-only pseudo-languages: shared query dirs without a grammar that real
  # queries pull in via `; inherits:` (javascript -> ecma,jsx; html, svelte,
  # vue, astro, ... -> html_tags). Upstream `:TSInstall` links them as
  # `requires` of the real languages; nixpkgs only ships queries attached to a
  # grammar, so these come straight from the plugin's runtime tree.
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

  mkTreesitterEnv =
    name: grammars:
    pkgs.buildEnv {
      inherit name;
      paths = [
        sharedQueries
      ]
      ++ grammars
      ++ lib.filter (q: q != null) (map (g: g.associatedQuery or null) grammars);
      # A query whose `; inherits:` target is missing from the env compiles
      # almost empty and nvim never complains; fail the build instead.
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
