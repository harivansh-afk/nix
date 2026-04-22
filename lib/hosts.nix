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
}
