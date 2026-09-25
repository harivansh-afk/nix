{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermes = config.services.hermes-agent;
  home = config.users.users.${hermes.user}.home;
  adapter = inputs.devin-codex.packages.${pkgs.stdenv.hostPlatform.system}.default;
  token = "/var/lib/hermes-devin/token";
in
{
  services.hermes-agent.settings = {
    model.provider = "devin";
    providers.devin = {
      base_url = "http://127.0.0.1:19476/v1";
      api_mode = "codex_responses";
      model = "gpt-6-astra";
      key_env = "DEVIN_CODEX_TOKEN";
      discover_models = false;
      context_length = 1000000;
    };
    secrets.command = {
      enabled = true;
      command = "${pkgs.coreutils}/bin/cat ${token}.env";
    };
  };

  systemd.services = {
    hermes-devin = {
      description = "Devin inference adapter for Hermes";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "exec";
        User = hermes.user;
        Group = hermes.group;
        StateDirectory = "hermes-devin";
        StateDirectoryMode = "0700";
        UMask = "0077";
        ExecStart = "${adapter}/bin/devin-codex --credentials ${home}/.local/share/devin/credentials.toml serve --devin ${home}/.local/bin/devin --port 19476 --token-file ${token} --compatibility";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "${home}/.local/share/devin/cli/logs" ];
      };
      preStart = ''
        if [ ! -e ${token} ]; then
          ${adapter}/bin/devin-codex token ${token}
        fi
        printf 'DEVIN_CODEX_TOKEN=%s\n' "$(cat ${token})" > ${token}.env
      '';
      postStart = ''
        printf 'Authorization: Bearer %s\n' "$(cat ${token})" |
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --retry 10 --retry-connrefused --retry-delay 1 --max-time 2 \
            --header @- --output /dev/null http://127.0.0.1:19476/healthz
      '';
    };
  }
  // lib.genAttrs [ "hermes-agent" "hermes-backend" ] (_: {
    requires = [ "hermes-devin.service" ];
    after = [ "hermes-devin.service" ];
  });
}
