{ lib, pkgs, ... }:
let
  sparkHostOptions = {
    user = "rathi";
    identityFile = "~/.ssh/id_ed25519";
    identitiesOnly = true;
    forwardAgent = true;
    controlMaster = "auto";
    controlPath = "~/.ssh/sockets/%r@%h:%p";
    controlPersist = "10m";
    serverAliveInterval = 60;
    serverAliveCountMax = 3;
  };

  ixHostOptions = {
    addKeysToAgent = "yes";
    forwardAgent = true;
    identitiesOnly = true;
    port = 9999;
    user = "hari";
  };

  ixHosts = {
    hil-compute-1 = "15.204.111.75";
    hil-compute-2 = "15.204.105.165";
    hil-stor-1 = "15.204.106.118";
    vin-compute-1 = "40.160.30.136";
    vin-compute-2 = "40.160.64.85";
    vin-stor-1 = "15.204.241.32";
  };

  ixMatchBlocks = builtins.mapAttrs (_: hostname: ixHostOptions // { inherit hostname; }) ixHosts;

  matchBlocks = {
    aurelius = {
      hostname = "100.71.160.102";
      user = "nixos";
      identityFile = "~/.ssh/id_ed25519";
    };

    spark = sparkHostOptions // {
      hostname = "spark";
      extraOptions.HostKeyAlias = "spark";
    };

    spark-lan = sparkHostOptions // {
      hostname = "192.168.0.6";
      extraOptions.HostKeyAlias = "spark";
    };
  }
  // ixMatchBlocks;

  # Render matchBlocks to ssh_config format.
  optMap = {
    addKeysToAgent = "AddKeysToAgent";
    controlMaster = "ControlMaster";
    controlPath = "ControlPath";
    controlPersist = "ControlPersist";
    forwardAgent = "ForwardAgent";
    hostname = "HostName";
    identitiesOnly = "IdentitiesOnly";
    identityFile = "IdentityFile";
    port = "Port";
    serverAliveCountMax = "ServerAliveCountMax";
    serverAliveInterval = "ServerAliveInterval";
    user = "User";
  };
  renderValue =
    v:
    if v == true then
      "yes"
    else if v == false then
      "no"
    else
      toString v;
  renderOpt = k: v: "  ${optMap.${k}} ${renderValue v}";
  renderExtraOpt = k: v: "  ${k} ${renderValue v}";
  renderBlock =
    name: opts:
    let
      regular = lib.filterAttrs (k: _: k != "extraOptions") opts;
      extra = opts.extraOptions or { };
    in
    lib.concatStringsSep "\n" (
      [ "Host ${name}" ]
      ++ (lib.mapAttrsToList renderOpt regular)
      ++ (lib.mapAttrsToList renderExtraOpt extra)
    );

  sshConfig = lib.concatStringsSep "\n\n" (lib.mapAttrsToList renderBlock matchBlocks) + "\n";
in
{
  packages = [ pkgs.openssh ];
  files.".ssh/config".text = sshConfig;
}
