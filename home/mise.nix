{...}: {
  programs.mise = {
    enable = true;
    globalConfig = {
      tools = {
        "npm:@openai/codex" = "latest";
      };
    };
  };
}
