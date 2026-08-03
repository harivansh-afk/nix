{ lib, pkgs, ... }:
let
  userConfig = import ../../modules/users/user-config.nix {
    inherit lib pkgs;
    user = {
      name = "root";
      homeDirectory = "/root";
    };
    dotsRoot = ../../dots;
    hostname = "ix";
    isDarwin = false;
    installMutableTools = false;
  };
in
{
  users.users.root.packages = userConfig.packages;

  system.activationScripts.userConfig-root = {
    deps = [
      "users"
      "groups"
    ];
    text = "${userConfig.script}";
  };
}
