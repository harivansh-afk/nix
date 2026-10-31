{ inputs, username, ... }:
{
  imports = [ inputs.rex.nixosModules.default ];

  services.rex.loginServer = {
    enable = true;
    accounts.${username}.principals = [ "tailscale:rathiharivansh@gmail.com" ];
    defaults."tailscale:rathiharivansh@gmail.com" = username;
    tailscaleServe.enable = true;
  };
}
