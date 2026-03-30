{
  config,
  pkgs,
  ...
}:
let
  defaultProfile = "default";
in
{
  home.packages = with pkgs; [
    docker-buildx
    docker-client
    docker-compose
  ];

  services.colima = {
    enable = true;
    colimaHomeDir = "${config.xdg.configHome}/colima";
    dockerPackage = pkgs.docker-client;

    profiles.${defaultProfile} = {
      isActive = true;
      isService = true;
      settings = {
        runtime = "docker";
        vmType = "qemu";
      };
    };
  };
}
