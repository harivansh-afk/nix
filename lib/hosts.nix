{ username }:
{
  darwin = {
    name = "darwin";
    kind = "darwin";
    system = "aarch64-darwin";
    hostname = "hari-macbook-pro";
    homeModule = ../home;
    homeDirectory = "/Users/${username}";
  };

  netty = {
    name = "netty";
    kind = "nixos";
    system = "x86_64-linux";
    hostname = "netty";
    homeModule = ../home/netty.nix;
    standaloneHomeModule = ../hosts/netty;
    homeDirectory = "/home/${username}";
  };
}
