{ pkgs, ... }:
let
  yamlFormat = pkgs.formats.yaml { };
  ghConfig = yamlFormat.generate "gh-config.yml" {
    git_protocol = "https";
    prompt = "enabled";
    prefer_editor_prompt = "disabled";
    aliases = {
      co = "pr checkout";
    };
  };
in
{
  packages = [ pkgs.gh ];
  files.".config/gh/config.yml".source = ghConfig;
}
