{ hostname, ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      custom_cpu_name = hostname;
      color_theme = "ayu";
      theme_background = false;
      vim_keys = true;
      rounded_corners = false;
    };
  };
}
