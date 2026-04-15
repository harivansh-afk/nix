{ ... }:
{
  programs.aerospace = {
    enable = true;

    launchd = {
      enable = true;
      keepAlive = true;
    };

    settings = {
      # Normalizations
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      # Layout defaults
      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      accordion-padding = 30;

      # Mouse follows focus when switching monitors
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      # Gaps between windows
      gaps = {
        inner.horizontal = 20;
        inner.vertical = 20;
        outer.left = 20;
        outer.right = 20;
        outer.top = 20;
        outer.bottom = 20;
      };

      # Auto-assign apps to workspaces
      on-window-detected = [
        # Browsers -> workspace 1
        {
          "if".app-id = "com.apple.Safari";
          run = "move-node-to-workspace 1";
        }
        {
          "if".app-id = "company.thebrowser.Browser";
          run = "move-node-to-workspace 1";
        }
        # Terminals -> workspace 2
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
        # Editors -> workspace 3
        {
          "if".app-id = "com.microsoft.VSCode";
          run = "move-node-to-workspace 3";
        }
        {
          "if".app-id = "dev.zed.Zed";
          run = "move-node-to-workspace 3";
        }
        # Chat -> workspace 4
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
        # Media -> workspace 5
        {
          "if".app-id = "com.spotify.client";
          run = "move-node-to-workspace 5";
        }
      ];

      mode.main.binding = {
        # Focus windows (arrow keys - alt+hjkl taken by Karabiner scroll)
        alt-left = "focus left";
        alt-down = "focus down";
        alt-up = "focus up";
        alt-right = "focus right";

        # Move windows
        alt-shift-left = "move left";
        alt-shift-down = "move down";
        alt-shift-up = "move up";
        alt-shift-right = "move right";

        # Switch workspaces
        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";

        # Move window to workspace
        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";

        # Layout toggles
        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";

        # Fullscreen
        alt-f = "fullscreen";

        # Float toggle
        alt-shift-f = "layout floating tiling";

        # Balance window sizes
        alt-shift-b = "balance-sizes";

        # Last workspace
        alt-backtick = "workspace-back-and-forth";

        # Monitor focus/move
        alt-period = "focus-monitor next";
        alt-shift-period = "move-node-to-monitor next";
        alt-shift-comma = "move-workspace-to-monitor next";

        # Modes
        alt-shift-r = "mode resize";
        alt-shift-semicolon = "mode service";

        # Screenshot to clipboard
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
