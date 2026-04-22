{ username }:
{
  macbook = {
    name = "macbook";
    kind = "darwin";
    system = "aarch64-darwin";
    hostname = "macbook";
    homeDirectory = "/Users/${username}";
    isDarwin = true;
    isLinux = false;
    isNixOS = false;
    features = {
      rust = true;
      go = true;
      node = true;
      python = true;
      aws = true;
      claude = true;
      docker = true;
      tex = true;
    };
  };

  netty = {
    name = "netty";
    kind = "nixos";
    system = "x86_64-linux";
    hostname = "netty";
    homeDirectory = "/home/${username}";
    isDarwin = false;
    isLinux = true;
    isNixOS = true;
    features = {
      rust = true;
      go = true;
      node = true;
      python = true;
      aws = true;
      claude = true;
      docker = false;
      tex = false;
    };
  };
}
