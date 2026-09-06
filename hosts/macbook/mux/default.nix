{
  lib,
  pkgs,
  inputs,
  username,
  ...
}:
let
  inherit (inputs) mux;
  ghostty = mux.inputs.ghostty;
  muxPkg = mux.packages.${pkgs.stdenv.hostPlatform.system}.muxd;
  home = "/Users/${username}";

  build = pkgs.writeShellScript "mux-app-build" ''
    export MUX_BUILD_ID="$0"
    export HOME=${lib.escapeShellArg home}
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${
      lib.makeBinPath [
        pkgs.zig_0_16
        pkgs.openssl
      ]
    }"
    export MUX_SRC=${mux} MUX_REV=${mux.rev}
    export GHOSTTY_SRC=${ghostty} GHOSTTY_REV=${ghostty.rev}
    export MUXD=${muxPkg} INFO_PLIST=${./Info.plist}
    exec ${./build.sh}
  '';
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    sudo -u ${username} ${build} || echo "warning: Mux build failed" >&2
  '';
}
