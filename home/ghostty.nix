{
  lib,
  pkgs,
  hostConfig,
  theme,
  ...
}:
let
  ghosttyConfig = ''
    theme = "cozybox-current"
    font-family = Berkeley Mono
    font-codepoint-map = U+f101-U+f25c=nonicons
    background-opacity = 1
    font-size = 17
    window-padding-y = 0
    window-padding-x = 0
    window-padding-color = extend
    mouse-scroll-multiplier = 1
    keybind = global:alt+space=toggle_visibility
    keybind = shift+enter=text:\n
    keybind = alt+v=activate_key_table:vim
    keybind = vim/
    keybind = vim/j=scroll_page_lines:1
    keybind = vim/k=scroll_page_lines:-1
    keybind = vim/ctrl+d=scroll_page_down
    keybind = vim/ctrl+u=scroll_page_up
    keybind = vim/ctrl+f=scroll_page_down
    keybind = vim/ctrl+b=scroll_page_up
    keybind = vim/shift+j=scroll_page_down
    keybind = vim/shift+k=scroll_page_up
    keybind = vim/g>g=scroll_to_top
    keybind = vim/shift+g=scroll_to_bottom
    keybind = vim/slash=start_search
    keybind = vim/n=navigate_search:next
    keybind = vim/v=copy_to_clipboard
    keybind = vim/y=copy_to_clipboard
    keybind = vim/shift+semicolon=toggle_command_palette
    keybind = vim/escape=deactivate_key_table
    keybind = vim/q=deactivate_key_table
    keybind = vim/i=deactivate_key_table
    keybind = vim/catch_all=ignore
    mouse-hide-while-typing = true
    ${lib.optionalString hostConfig.isDarwin ''
      macos-titlebar-style = hidden
      macos-option-as-alt = true
    ''}
    confirm-close-surface = true
    window-title-font-family = VictorMono NFM Italic
    window-padding-balance = true
    window-save-state = always
    shell-integration-features = true
    copy-on-select = clipboard
    focus-follows-mouse = true
    link-url = true
  '';
in
{
  programs.ghostty = {
    enable = true;
    package = if hostConfig.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    installBatSyntax = true;
  };

  xdg.configFile."ghostty/config" = {
    text = ghosttyConfig;
    force = true;
  };

  xdg.configFile."ghostty/themes/cozybox-dark".text = theme.renderGhostty "dark";
  xdg.configFile."ghostty/themes/cozybox-light".text = theme.renderGhostty "light";

  home.file = lib.mkIf hostConfig.isDarwin {
    "Library/Application Support/com.mitchellh.ghostty/config.ghostty" = {
      text = ghosttyConfig;
      force = true;
    };
  };
}
