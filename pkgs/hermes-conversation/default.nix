{ pkgs }:
pkgs.runCommand "hermes-conversation-0.1.0" { } ''
  mkdir -p $out
  cp ${./hermes_conversation}/*.py ${./hermes_conversation}/plugin.yaml $out/
''
