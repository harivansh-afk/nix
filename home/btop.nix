{ hostname, ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      custom_cpu_name = hostname;
    };
  };
}
