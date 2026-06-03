{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = 6060;
  modelId = "nvidia/parakeet-tdt-0.6b-v3";
  stateDir = "/var/lib/parakeet";
  venv = "${stateDir}/venv";
  server = "${stateDir}/server.py";

  # The fast path on this box is the GB10 GPU. Parakeet runs via transformers on
  # torch built for CUDA 13 / Blackwell (sm_121). Those wheels are not in
  # nixpkgs, so the runtime is bootstrapped into a uv venv on first start
  # (mirrors how inference.nix fetches its model at runtime). torch comes from
  # the cu130 nightly index; everything else is pinned.
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

  # Bump REQ_VERSION to force a venv reinstall after changing deps.
  reqVersion = "1";
  setup = pkgs.writeShellScript "parakeet-setup" ''
    set -euo pipefail
    export PATH=${runtimeBins}:$PATH

    install -m0644 ${./../../dots/parakeet/server.py} ${server}

    if [ "$(cat ${stateDir}/.req-version 2>/dev/null || true)" != "${reqVersion}" ] || [ ! -x ${venv}/bin/python ]; then
      uv venv --python ${python}/bin/python3.12 ${venv}
      # torch for CUDA 13 / Blackwell from the nightly index
      uv pip install --python ${venv}/bin/python --prerelease=allow \
        --index-url https://download.pytorch.org/whl/nightly/cu130 torch
      # everything else from PyPI
      uv pip install --python ${venv}/bin/python \
        'transformers==5.9.0' soundfile librosa numpy \
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

  # OpenAI-compatible Parakeet speech-to-text on the GB10 GPU, loopback only.
  systemd.services.parakeet = {
    description = "Parakeet GPU speech-to-text (OpenAI-compatible)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      # Driver libcuda + manylinux runtime libs (systemd has no nix-ld env).
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:${runtimeLibs}";
      # triton resolves libcuda here instead of calling /sbin/ldconfig.
      TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";
      HF_HOME = "${stateDir}/hf";
      PARAKEET_MODEL_ID = modelId;
      PATH = lib.mkForce "${runtimeBins}";
    };
    serviceConfig = {
      Type = "simple";
      ExecStartPre = setup;
      ExecStart = "${venv}/bin/python -u -m uvicorn server:app --host 127.0.0.1 --port ${toString port}";
      WorkingDirectory = stateDir;
      Restart = "on-failure";
      RestartSec = 5;
      # First start downloads torch (~5GB) and the model (~2.4GB).
      TimeoutStartSec = "2400";
      OOMScoreAdjust = 500;
    };
  };

  # OpenWhispr rejects plain-HTTP remote endpoints, so expose over Tailscale
  # HTTPS (valid *.ts.net cert). Requires HTTPS certificates enabled for the
  # tailnet (Tailscale admin console > DNS > HTTPS Certificates).
  systemd.services.parakeet-tailscale-serve = {
    description = "Expose parakeet over Tailscale HTTPS";
    after = [
      "parakeet.service"
      "tailscaled.service"
    ];
    wants = [ "parakeet.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg ${toString port}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
    };
  };
}
