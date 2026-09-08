{ config, pkgs, ... }:
{
  services.hermes-agent = {
    extraPlugins = [
      (pkgs.fetchFromGitHub {
        name = "relay-hermes";
        owner = "RelayMessenger";
        repo = "Relay-Hermes";
        rev = "002b12cd0fa6e0f7ece7f90f57de6c11bd035bf5";
        hash = "sha256-+dDlPeJwlAalAn/oM3vK9k7qdVt+LWg5mwMV0Hf3G5I=";
      })
    ];
    environmentFiles = [ config.sops.secrets."hermes-relay.env".path ];
    settings = {
      platform_toolsets.relayapp = config.services.hermes-agent.settings.platform_toolsets.photon;
    };
  };
}
