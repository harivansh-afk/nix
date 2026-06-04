{ lib, username }:
let
  inherit (lib) mkOption types;
in
types.submodule (
  { name, config, ... }:
  {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
      };

      kind = mkOption {
        type = types.enum [
          "darwin"
          "nixos"
        ];
      };

      system = mkOption {
        type = types.enum [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];
      };

      hostname = mkOption {
        type = types.str;
        default = name;
      };

      roles = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };

      homeDirectory = mkOption {
        type = types.str;
        default = if config.isDarwin then "/Users/${username}" else "/home/${username}";
      };

      isDarwin = mkOption {
        type = types.bool;
        default = config.kind == "darwin";
        readOnly = true;
      };

      isLinux = mkOption {
        type = types.bool;
        default = config.kind != "darwin";
        readOnly = true;
      };

      isNixOS = mkOption {
        type = types.bool;
        default = config.kind == "nixos";
        readOnly = true;
      };
    };
  }
)
