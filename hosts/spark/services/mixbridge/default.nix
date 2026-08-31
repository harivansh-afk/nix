# yt-dlp extraction API for the mixbridge iOS app: SoundCloud stream URLs and
# server-side HLS downloads, Spotify metadata with YouTube-sourced audio.
# main.py is vendored from ytdlp-api in the mixbridge monorepo - keep in sync.
# Same runtime-uv-venv pattern as whisper: yt-dlp extractors break often, so
# updating it must not wait on a nixpkgs bump (edit setup.sh, bump reqVersion).
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
  reqVersion = "1";
  runtimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.ffmpeg
    pkgs.coreutils
  ];
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
  ];

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
      REQ_VERSION = reqVersion;
    };
    serviceConfig = {
      WorkingDirectory = stateDir;
      # SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET
      EnvironmentFile = config.sops.secrets."mixbridge.env".path;
      ExecStartPre = "${pkgs.bash}/bin/bash ${./setup.sh}";
      ExecStart = "${venv}/bin/python -u -m uvicorn main:app --host 127.0.0.1 --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "600";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  services.caddy.virtualHosts."http://${domain}" = loopbackVhost port;
}
