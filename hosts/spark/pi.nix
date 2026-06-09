{ inputs, pkgs, ... }:
let
  models = ../../dots/pi/models.json;
  ixMcp = pkgs.writeShellScriptBin "ix-mcp" ''
    exec nix run --accept-flake-config /home/rathi/Documents/Git/indexable/index#mcp -- "$@"
  '';
  ixMcpBridge = pkgs.buildNpmPackage {
    pname = "ix-mcp-bridge";
    version = "0.1.0";
    src = inputs.index + "/packages/pi-harness/extension";
    npmDepsHash = "sha256-Nis7wQLp7wASaEu4n/Cp3pthB3z+9FsTJs5pK3oq77M=";
    dontNpmBuild = true;
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm test
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp ix-mcp-bridge.ts env.js package.json $out/
      cp -r node_modules $out/node_modules
      runHook postInstall
    '';
  };
in
{
  imports = [
    inputs.pi-mono.nixosModules.default
  ];

  environment.systemPackages = [ ixMcp ];

  programs.pi.coding-agent = {
    enable = true;
    extensions = [ "${ixMcpBridge}/ix-mcp-bridge.ts" ];
    models = null;
    settings = {
      defaultProvider = "openai";
      defaultModel = "gpt-5.5";
    };
    extraArgs = [
      "--no-builtin-tools"
      "--provider"
      "openai"
      "--model"
      "gpt-5.5"
    ];
  };

  systemd.user.tmpfiles.users.rathi.rules = [
    "d %h/.pi 0700 - - -"
    "d %h/.pi/agent 0700 - - -"
    "L+ %h/.pi/agent/models.json - - - - ${models}"
  ];
}
