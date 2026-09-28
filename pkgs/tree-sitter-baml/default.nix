{
  lib,
  tree-sitter,
  fetchFromGitHub,
}:
tree-sitter.buildGrammar {
  language = "baml";
  version = "0.1.0+rev=276b4d8";
  src = fetchFromGitHub {
    owner = "BoundaryML";
    repo = "baml-treesitter";
    rev = "276b4d8471f1c2f2ce80f182ab46d171b825f2b7";
    hash = "sha256-iV5+HiqYFUGLvnp3VYTz7oVjIQZcoUsalXiITyQL+l4=";
  };
  meta = {
    homepage = "https://github.com/BoundaryML/baml-treesitter";
    license = lib.licenses.asl20;
  };
}
