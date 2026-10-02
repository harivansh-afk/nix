{ lib, pkgs }:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  cua = if isLinux then pkgs.callPackage ../cua-cli { } else null;
  settings = pkgs.writeText "com-computer-settings.json" (
    builtins.toJSON {
      podman = if isLinux then lib.getExe pkgs.podman else "";
      cua = if isLinux then lib.getExe cua else "";
      ssh = lib.getExe pkgs.openssh;
      ssh_config = ../../dots/ssh/config;
      git = lib.getExe pkgs.git;
      image = "ghcr.io/trycua/linux@sha256:f5306ce817ba495838a362a0249bbe683afcbc3f0996b9c05714ca007bb23302";
    }
  );
in
pkgs.runCommand "com-computer"
  {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    meta = {
      description = "Codex with Devin inference and a dedicated desktop";
      mainProgram = "com-computer";
      platforms = [
        "aarch64-linux"
        "aarch64-darwin"
      ];
    };
  }
  ''
    mkdir -p $out/bin $out/lib/com-computer
    cp ${./computer.py} $out/lib/com-computer/computer.py
    cp ${./instructions.md} $out/lib/com-computer/instructions.md
    cp ${settings} $out/lib/com-computer/settings.json
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/com-computer \
      --add-flags "$out/lib/com-computer/computer.py"
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/com-computer-codex \
      --add-flags "$out/lib/com-computer/computer.py _codex"
  ''
