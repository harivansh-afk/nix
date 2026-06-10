{ lib, username }:
let
  nodeType = import ./schema.nix { inherit lib username; };

  nodesDir = ./nodes;
  nodeFiles = lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".nix" file) (
    builtins.readDir nodesDir
  );
  nodeData = lib.mapAttrs' (
    file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import (nodesDir + "/${file}"))
  ) nodeFiles;

  evaluated = lib.evalModules {
    modules = [
      { options.nodes = lib.mkOption { type = lib.types.attrsOf nodeType; }; }
      { config.nodes = nodeData; }
    ];
  };

  inherit (evaluated.config) nodes;

  invariants = lib.flatten (
    lib.mapAttrsToList (name: node: [
      (lib.assertMsg (
        node.name == name
      ) "inventory: node '${name}' sets name to '${node.name}'; the name field must match its file")
      (lib.assertMsg (
        node.isDarwin -> lib.hasSuffix "-darwin" node.system
      ) "inventory: node '${name}' is kind=darwin but system '${node.system}' is not a darwin platform")
      (lib.assertMsg (
        node.isNixOS -> lib.hasSuffix "-linux" node.system
      ) "inventory: node '${name}' is kind=nixos but system '${node.system}' is not a linux platform")
    ]) nodes
  );
in
assert lib.all (check: check) invariants;
nodes
