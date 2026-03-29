{...}: {
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;

    settings = {
      git_protocol = "https";
      prompt = "enabled";
      prefer_editor_prompt = "disabled";

      aliases = {
        co = "pr checkout";
      };
    };
  };
}
