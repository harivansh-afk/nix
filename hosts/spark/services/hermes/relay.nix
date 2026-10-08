{
  config,
  lib,
  pkgs,
  ...
}:
let
  hermes = config.services.hermes-agent;
  profileHome = "${hermes.stateDir}/.hermes/profiles/imessage";
  secret = config.sops.secrets."hermes-relay.env";
in
{
  services.hermes-agent.extraPlugins = [
    (pkgs.fetchFromGitHub {
      name = "relay-hermes";
      owner = "RelayMessenger";
      repo = "Relay-Hermes";
      rev = "48c01a4ddabfcef7f23226bcad3c11f56504feaa";
      hash = "sha256-70UB5mKTdm0+hwnrzdTucsA6wV6/qsoIqnv5GVPPQ0U=";
    })
  ];

  system.activationScripts.hermes-relay-profile = lib.stringAfter [ "hermes-agent-setup" ] ''
    install -o ${hermes.user} -g ${hermes.group} -m 0600 ${secret.path} ${profileHome}/.env
  '';

  systemd.services.hermes-agent.restartTriggers = [ secret.sopsFile ];
}
