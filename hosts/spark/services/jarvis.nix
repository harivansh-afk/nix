{ config, inputs, ... }:
{
  imports = [ inputs.jarvis.nixosModules.default ];

  services.jarvis = {
    enable = true;
    user = "rathi";
    muxPackage = config.services.muxd.package;
  };

  programs.git.config.url."ssh://git@jarvis-source/harivansh-afk/jarvis.git".insteadOf =
    "https://git.harivan.sh/harivansh-afk/jarvis.git";

  programs.ssh = {
    knownHosts.jarvis-source.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInBl/uBMMYrSLNhZ+ObB2pELWtuTyPslzgS2NdjkyhR";
    extraConfig = ''
      Host jarvis-source
        HostName 127.0.0.1
        HostKeyAlias jarvis-source
        User git
      Match originalhost jarvis-source localuser root,gitea-runner
        IdentityFile ${config.sops.secrets.jarvis-deploy-key.path}
        IdentitiesOnly yes
        IdentityAgent none
      Match all
    '';
  };
}
