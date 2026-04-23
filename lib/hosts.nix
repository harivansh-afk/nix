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
      docker = true;
    };
  };

  spark = {
    name = "spark";
    kind = "nixos";
    system = "aarch64-linux";
    hostname = "spark";
    homeDirectory = "/home/${username}";
    isDarwin = false;
    isLinux = true;
    isNixOS = true;
    features = {
      rust = true;
      go = true;
      node = true;
      python = true;
      docker = true;
    };
  };
}
