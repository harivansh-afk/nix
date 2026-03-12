{pkgs, ...}: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    installBatSyntax = true;

    settings = {
      theme = "Gruvbox Material Dark";
      "font-family" = "Berkeley Mono";
      "font-codepoint-map" = "U+f101-U+f25c=nonicons";
      "background-opacity" = 1;
      "font-size" = 17;
      "window-padding-y" = 0;
      "window-padding-x" = 0;
      "window-padding-color" = "extend";
      "mouse-scroll-multiplier" = 1;
      keybind = [
        "global:alt+space=toggle_visibility"
        "shift+enter=text:\\n"
        "alt+v=activate_key_table:vim"
        "vim/"
        "vim/j=scroll_page_lines:1"
        "vim/k=scroll_page_lines:-1"
        "vim/ctrl+d=scroll_page_down"
        "vim/ctrl+u=scroll_page_up"
        "vim/ctrl+f=scroll_page_down"
        "vim/ctrl+b=scroll_page_up"
        "vim/shift+j=scroll_page_down"
        "vim/shift+k=scroll_page_up"
        "vim/g>g=scroll_to_top"
        "vim/shift+g=scroll_to_bottom"
        "vim/slash=start_search"
        "vim/n=navigate_search:next"
        "vim/v=copy_to_clipboard"
        "vim/y=copy_to_clipboard"
        "vim/shift+semicolon=toggle_command_palette"
        "vim/escape=deactivate_key_table"
        "vim/q=deactivate_key_table"
        "vim/i=deactivate_key_table"
        "vim/catch_all=ignore"
      ];
      "mouse-hide-while-typing" = true;
      "macos-titlebar-style" = "hidden";
      "macos-option-as-alt" = true;
      "confirm-close-surface" = true;
      "window-title-font-family" = "VictorMono NFM Italic";
      "window-padding-balance" = true;
      "window-save-state" = "always";
      "shell-integration-features" = true;
      "copy-on-select" = "clipboard";
      "focus-follows-mouse" = true;
      "link-url" = true;
    };
  };
}
