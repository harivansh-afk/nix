{ ... }:
{
  programs.aerospace = {
    enable = true;

    launchd = {
      enable = true;
      keepAlive = true;
    };

    settings = {
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      accordion-padding = 30;

      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      gaps = {
        inner.horizontal = 0;
        inner.vertical = 0;
        outer.left = 0;
        outer.right = 0;
        outer.top = 0;
        outer.bottom = 0;
      };

      on-window-detected = [
        {
          "if".app-id = "com.apple.Safari";
          run = "move-node-to-workspace 1";
        }
        {
          "if".app-id = "company.thebrowser.Browser";
          run = "move-node-to-workspace 1";
        }
        {
          "if".app-id = "com.apple.Terminal";
          run = "move-node-to-workspace 2";
        }
        {
          "if".app-id = "com.mitchellh.ghostty";
          run = "move-node-to-workspace 2";
        }
        {
          "if".app-id = "com.googlecode.iterm2";
          run = "move-node-to-workspace 2";
        }
        {
          "if".app-id = "com.microsoft.VSCode";
          run = "move-node-to-workspace 3";
        }
        {
          "if".app-id = "dev.zed.Zed";
          run = "move-node-to-workspace 3";
        }
        {
          "if".app-id = "com.tinyspeck.slackmacgap";
          run = "move-node-to-workspace 4";
        }
        {
          "if".app-id = "ru.keepcoder.Telegram";
          run = "move-node-to-workspace 4";
        }
        {
          "if".app-id = "org.whispersystems.signal-desktop";
          run = "move-node-to-workspace 4";
        }
        {
          "if".app-id = "com.apple.MobileSMS";
          run = "move-node-to-workspace 4";
        }
        {
          "if".app-id = "com.spotify.client";
          run = "move-node-to-workspace 5";
        }
      ];

      mode.main.binding = {
        alt-left = "focus left";
        alt-down = "focus down";
        alt-up = "focus up";
        alt-right = "focus right";

        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-left = "move left";
        alt-shift-down = "move down";
        alt-shift-up = "move up";
        alt-shift-right = "move right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";

        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";

        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";

        alt-f = "fullscreen";

        alt-shift-f = "layout floating tiling";

        alt-shift-b = "balance-sizes";

        alt-backtick = "workspace-back-and-forth";

        alt-period = "focus-monitor --wrap-around next";
        alt-shift-period = "move-node-to-monitor --wrap-around --focus-follows-window next";
        alt-shift-comma = "move-workspace-to-monitor --wrap-around next";
        ctrl-alt-cmd-space = "move-node-to-monitor --wrap-around --focus-follows-window next";

        alt-r = "mode resize";
        alt-shift-semicolon = "mode service";

        alt-shift-s = "exec-and-forget screencapture -i -c";
      };

      mode.resize.binding = {
        h = "resize width -50";
        j = "resize height +50";
        k = "resize height -50";
        l = "resize width +50";
        minus = "resize smart -50";
        equal = "resize smart +50";
        enter = "mode main";
        esc = "mode main";
      };

      mode.service.binding = {
        r = [
          "reload-config"
          "mode main"
        ];
        f = [
          "flatten-workspace-tree"
          "mode main"
        ];
        b = [
          "balance-sizes"
          "mode main"
        ];
        esc = "mode main";
        backspace = [
          "close-all-windows-but-current"
          "mode main"
        ];
      };
    };
  };
}
