{
  lib,
  pkgs,
  config,
  loopbackVhost,
  ...
}:
let
  domain = "mixbridge.harivan.sh";
  port = 19400;
  stateDir = "/var/lib/mixbridge";
  venv = "${stateDir}/venv";
  reqVersion = "2";
  runtimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.ffmpeg
    pkgs.coreutils
  ];
in
{
  systemd.services.mixbridge-api = {
    description = "mixbridge yt-dlp extraction API";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PATH = lib.mkForce runtimeBins;
      STATE_DIR = stateDir;
      VENV = venv;
      PYTHON = "${pkgs.python312}/bin/python3.12";
      APP_PY = ./main.py;
      AUTH_PY = ./auth.py;
      REQ_VERSION = reqVersion;
      UV_CACHE_DIR = "${stateDir}/uv-cache";
    };
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "mixbridge";
      StateDirectoryMode = "0750";
      WorkingDirectory = stateDir;
      # SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET
      EnvironmentFile = config.sops.secrets."mixbridge.env".path;
      ExecStartPre = "${pkgs.bash}/bin/bash ${./setup.sh}";
      ExecStart = "${venv}/bin/python -u -m uvicorn main:app --host 127.0.0.1 --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "600";
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      CapabilityBoundingSet = "";
      MemoryMax = "1G";
      TasksMax = 128;
      NoNewPrivileges = true;
    };
  };

  services.caddy.virtualHosts."http://${domain}" = loopbackVhost port;
}
