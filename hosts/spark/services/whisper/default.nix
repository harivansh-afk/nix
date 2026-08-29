# Whisper large-v3 on the GPU, OpenAI-compatible, served over Tailscale
# HTTPS for VoiceInk on the mac.
{ lib, pkgs, ... }:
let
  port = 6060;
  stateDir = "/var/lib/whisper";
  venv = "${stateDir}/venv";
  reqVersion = "1";
  runtimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.ffmpeg
    pkgs.coreutils
  ];
  runtimeLibs = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${stateDir}/hf 0750 root root -"
  ];

  systemd.services.whisper = {
    description = "Whisper GPU speech-to-text (OpenAI-compatible)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PATH = lib.mkForce runtimeBins;
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:${runtimeLibs}";
      HF_HOME = "${stateDir}/hf";
      WHISPER_MODEL_ID = "openai/whisper-large-v3";
      STATE_DIR = stateDir;
      VENV = venv;
      PYTHON = "${pkgs.python312}/bin/python3.12";
      SERVER_PY = ./server.py;
      REQ_VERSION = reqVersion;
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = stateDir;
      ExecStartPre = "${pkgs.bash}/bin/bash ${./setup.sh}";
      ExecStart = "${venv}/bin/python -u -m uvicorn server:app --host 127.0.0.1 --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = "2400";
      OOMScoreAdjust = 500;
    };
  };

  systemd.services.whisper-tailscale-serve = {
    description = "Expose Whisper over Tailscale HTTPS";
    after = [
      "whisper.service"
      "tailscaled.service"
    ];
    wants = [
      "whisper.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale wait --timeout=2m";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg ${toString port}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
