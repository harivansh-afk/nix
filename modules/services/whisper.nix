{
  lib,
  pkgs,
  ...
}:
let
  port = 6060;
  modelId = "openai/whisper-large-v3";
  stateDir = "/var/lib/whisper";
  venv = "${stateDir}/venv";
  server = "${stateDir}/server.py";
  python = pkgs.python312;
  runtimeLibs = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];
  runtimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.ffmpeg
    pkgs.coreutils
  ];
  reqVersion = "1";
  setup = pkgs.writeShellScript "whisper-setup" ''
    set -euo pipefail
    export PATH=${runtimeBins}:$PATH

    install -m0644 ${./../../dots/whisper/server.py} ${server}

    if [ "$(cat ${stateDir}/.req-version 2>/dev/null || true)" != "${reqVersion}" ] || [ ! -x ${venv}/bin/python ]; then
      uv venv --python ${python}/bin/python3.12 ${venv}
      uv pip install --python ${venv}/bin/python --prerelease=allow \
        --index-url https://download.pytorch.org/whl/nightly/cu130 torch
      uv pip install --python ${venv}/bin/python \
        'transformers==5.9.0' accelerate soundfile librosa numpy \
        fastapi 'uvicorn[standard]' python-multipart huggingface_hub
      printf '%s' "${reqVersion}" > ${stateDir}/.req-version
    fi
  '';
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
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:${runtimeLibs}";
      HF_HOME = "${stateDir}/hf";
      WHISPER_MODEL_ID = modelId;
      PATH = lib.mkForce runtimeBins;
    };
    serviceConfig = {
      Type = "simple";
      ExecStartPre = setup;
      ExecStart = "${venv}/bin/python -u -m uvicorn server:app --host 127.0.0.1 --port ${toString port}";
      WorkingDirectory = stateDir;
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
    wants = [ "whisper.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg ${toString port}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };
}
