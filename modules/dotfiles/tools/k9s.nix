{ pkgs, ... }:
let
  yamlFormat = pkgs.formats.yaml { };
  views = yamlFormat.generate "k9s-views.yaml" {
    views = {
      "v1/pods".columns = [
        "NAME"
        "USER:.metadata.labels.handle"
        "STATUS"
        "READY"
        "AGE"
      ];
    };
  };
in
{
  packages = [ pkgs.k9s ];
  files.".config/k9s/views.yaml".source = views;
}
