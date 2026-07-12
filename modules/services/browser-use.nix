{
  lib,
  pkgs,
  ...
}:
# browser-use.nix - native, fully-local web automation.
#
# A `browse "<task>"` CLI that drives a real headless Chromium with browser-use,
# reasoning over the page with the LOCAL brain (inference.nix, qwen3.6-35b-a3b at
# 127.0.0.1:18080). No cloud API, no network exposure, no ports.
#
# Two NixOS-specific constraints shape this module:
#
#   1. The brain is TEXT-ONLY (no vision/mmproj), so the agent MUST run in
#      DOM-extraction mode. The runner forces use_vision=False, which makes
#      browser-use feed the serialized DOM to the model instead of screenshots.
#
#   2. browser-use 0.13.x dropped Playwright: it launches Chromium itself over
#      CDP. So instead of the playwright-driver browser bundle, we point it at
#      the nix-store Chromium directly (BROWSER_USE_CHROMIUM=${pkgs.chromium}).
#      Nothing is ever downloaded at runtime except the pip deps on first start.
#
# The runtime is bootstrapped into a uv venv on first use (mirrors
# knowledge-base.nix / whisper.nix), gated on a req-version file.
let
  stateDir = "/var/lib/browser-use";
  venv = "${stateDir}/venv";
  runner = "${stateDir}/run_task.py";
  # Persistent profile dir for logged-in sessions (e.g. X). Created below; the
  # `browse` wrapper points browser-use at it so cookies survive across runs.
  profileDir = "${stateDir}/profile";

  python = pkgs.python312;

  # Bump to force a venv reinstall after changing deps.
  reqVersion = "1";
  # Pinned to the current stable on PyPI at authoring time. Bump deliberately.
  pkgVersion = "0.13.1";

  runtimeBins = lib.makeBinPath [
    pkgs.uv
    pkgs.coreutils
    pkgs.gcc
    pkgs.binutils
  ];
  # libstdc++/libgcc for the manylinux wheels browser-use pulls (pydantic-core,
  # the cdp core, etc.); chromium itself is the nixpkgs wrapper and self-resolves.
  runtimeLibs = lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
  ];

  chromiumBin = "${pkgs.chromium}/bin/chromium";

  setup = pkgs.writeShellScript "browser-use-setup" ''
    set -euo pipefail
    export PATH=${runtimeBins}:$PATH

    install -m0644 ${./../../dots/browser-use/run_task.py} ${runner}

    if [ "$(cat ${stateDir}/.req-version 2>/dev/null || true)" != "${reqVersion}" ] || [ ! -x ${venv}/bin/python ]; then
      uv venv --clear --python ${python}/bin/python3.12 ${venv}
      uv pip install --python ${venv}/bin/python "browser-use==${pkgVersion}"
      printf '%s' "${reqVersion}" > ${stateDir}/.req-version
    fi
  '';

  # `browse "<task>"`: run one headless browser-use task against the local brain
  # and print the final result text. Loopback only; no ports, no exposure.
  # Bootstraps the venv on first call so it works for an interactive user too,
  # not only via the browser-use-setup unit.
  browse = pkgs.writeShellScriptBin "browse" ''
    set -euo pipefail
    if [ "$#" -eq 0 ]; then
      echo "usage: browse \"<task>\"" >&2
      exit 2
    fi

    export PATH=${runtimeBins}:$PATH
    # Driver libcuda is not needed (chromium runs on CPU here); just the
    # manylinux runtime libs for the venv's native wheels.
    export LD_LIBRARY_PATH=${runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Bootstrap the venv if missing (first interactive use before the unit ran).
    if [ ! -x ${venv}/bin/python ]; then
      ${setup}
    fi

    export BROWSER_USE_CHROMIUM=${chromiumBin}
    export BROWSER_USE_BRAIN_URL=http://127.0.0.1:18080/v1
    export BROWSER_USE_BRAIN_MODEL=qwen3.6-35b-a3b
    # Use a persistent profile when present so logged-in sessions (X) are reused.
    if [ -d ${profileDir} ]; then
      export BROWSER_USE_PROFILE_DIR=${profileDir}
    fi
    # browser-use writes config/cache under $HOME; keep it inside the state dir.
    export HOME="''${HOME:-${stateDir}}"
    export BROWSER_USE_SETUP_LOGGING=false

    exec ${venv}/bin/python ${runner} "$@"
  '';
in
{
  # 0755 (world-traversable): the venv + state are root-owned, but the `browse`
  # CLI and the mini-loops (which run as the user `rathi`) must be able to
  # traverse here and exec the venv python. 0750 root:root locked them out.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root -"
    "d ${profileDir} 0755 root root -"
  ];

  # Expose the CLI for the user (browse-x-login uses this venv too).
  environment.systemPackages = [ browse ];

  # Build the venv once at boot so the first `browse` call is fast. Oneshot so
  # consumers (e.g. browse-x-login) can depend on it.
  systemd.services.browser-use-setup = {
    description = "Bootstrap the browser-use uv venv";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = setup;
      # First run resolves + installs the browser-use dependency tree.
      TimeoutStartSec = "1800";
    };
  };
}
