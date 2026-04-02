{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
lib.mkIf (!hostConfig.isDarwin) {
  # agent-browser user-level config: point at nix chromium, run headless
  home.file.".agent-browser/config.json".text = builtins.toJSON {
    executablePath = "${pkgs.chromium}/bin/chromium";
    args = "--no-sandbox,--disable-gpu,--disable-dev-shm-usage";
  };

  # Install agent-browser globally via npm at activation time.
  # npm's postinstall symlinks the glibc binary, which fails on NixOS
  # (no /lib64/ld-linux-x86-64.so.2).  Re-point the symlink at the
  # statically-linked musl binary that works everywhere.
  home.activation.installAgentBrowser = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${
      lib.makeBinPath [
        pkgs.nodejs_22
        pkgs.coreutils
      ]
    }:$PATH"

    npm_prefix="$(npm prefix -g 2>/dev/null)"
    npm_bin="$npm_prefix/bin"
    pkg_bin="$npm_prefix/lib/node_modules/agent-browser/bin"

    if [ ! -e "$pkg_bin/agent-browser-linux-musl-x64" ]; then
      npm install -g agent-browser 2>/dev/null || true
    fi

    # Fix: replace glibc symlink with statically-linked musl binary
    if [ -e "$pkg_bin/agent-browser-linux-musl-x64" ]; then
      chmod +x "$pkg_bin/agent-browser-linux-musl-x64" 2>/dev/null || true
      ln -sf "$pkg_bin/agent-browser-linux-musl-x64" "$npm_bin/agent-browser"
    fi
  '';
}
