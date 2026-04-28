{
  lib,
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
    font-size = 15
    window-padding-y = 0
    window-padding-x = 0
    window-padding-color = extend
    mouse-scroll-multiplier = 1
    keybind = global:alt+space=toggle_visibility
    keybind = shift+enter=text:\x0a
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
  xdg.configFile."ghostty/config" = {
    text = ghosttyConfig;
    force = true;
  };

  xdg.configFile."ghostty/themes/cozybox-dark".text = theme.renderGhostty "dark";
  xdg.configFile."ghostty/themes/cozybox-light".text = theme.renderGhostty "light";

  home.file = lib.mkIf hostConfig.isDarwin {
    "Library/Application Support/com.mitchellh.ghostty/config" = {
      text = ghosttyConfig;
      force = true;
    };
  };
}
