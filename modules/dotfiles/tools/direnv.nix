{ pkgs, lib, ... }:
{
  packages = with pkgs; [
    direnv
    nix-direnv
  ];

  files.".config/direnv/direnv.toml".text = ''
    [global]
    hide_env_diff = true
  '';

  files.".config/direnv/direnvrc".text = ''
    source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
  '';

  # silent = true in HM is achieved by exporting DIRENV_LOG_FORMAT=""
  sessionVars.DIRENV_LOG_FORMAT = "";

  zshInit = lib.mkOrder 850 ''
    eval "$(${pkgs.direnv}/bin/direnv hook zsh)"
  '';
}
