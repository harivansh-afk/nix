{
  pkgs,
  username,
  ...
}: {
  nix.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "@admin"
      username
    ];
  };

  nix.gc = {
    automatic = true;
    interval = {
      Weekday = 7;
      Hour = 3;
      Minute = 0;
    };
    options = "--delete-older-than 14d";
  };

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;
  environment.shells = [pkgs.zsh];

  environment.systemPackages = with pkgs; [
    curl
    fd
    fzf
    gnupg
    go_1_26
    jq
    just
    nodejs_22
    python3
    ripgrep
    rustup
    tree
    uv
    wget
    zoxide
  ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
