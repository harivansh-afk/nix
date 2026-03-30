{ lib, ... }:
{
  xdg.configFile."gcloud/active_config".text = "default\n";

  xdg.configFile."gcloud/configurations/config_default".text = lib.generators.toINI { } {
    core = {
      account = "rathiharivansh@gmail.com";
      project = "hari-gc";
    };
  };
}
