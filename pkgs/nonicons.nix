{ fetchFromGitHub, runCommand }:
let
  src = fetchFromGitHub {
    owner = "ya2s";
    repo = "nonicons";
    rev = "a7d49eef27d1143b03a4eeb33859f411b9e93490";
    hash = "sha256-2eTjf7tl85YJkJY99Pb3a5PBhfPRUHIXXvAwfTPgnwc=";
  };
in
runCommand "nonicons" { } ''
  install -Dm644 ${src}/dist/nonicons.ttf $out/share/fonts/truetype/nonicons.ttf
''
