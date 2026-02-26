{ config, lib, ... }:

let
  mkActionBinds = action: keys:
    lib.listToAttrs (map (key: lib.nameValuePair key { inherit action; }) keys);

  mkLockedSpawnShBinds = spawnSh: bindings:
    lib.listToAttrs (
      map (binding:
        lib.nameValuePair binding.key {
          action = spawnSh binding.cmd;
          allow-when-locked = true;
        }
      ) bindings
    );

  mkWorkspaceBinds = field: prefix:
    lib.listToAttrs (
      map (index:
        lib.nameValuePair "${prefix}${toString index}" {
          action = { "${field}" = index; };
        }
      ) (lib.range 1 9)
    );

  mergeMany = lib.foldl' (acc: item: acc // item) { };
in
{
  programs.niri.settings.binds = with config.lib.niri.actions;
    let
      directionDefs = [
        {
          arrow = "Left";
          vim = "H";
          focusAction = focus-column-left;
          moveAction = move-column-left;
          monitorFocusAction = focus-monitor-left;
          monitorMoveAction = move-column-to-monitor-left;
        }
        {
          arrow = "Down";
          vim = "J";
          focusAction = focus-window-down;
          moveAction = move-window-down;
          monitorFocusAction = focus-monitor-down;
          monitorMoveAction = move-column-to-monitor-down;
        }
        {
          arrow = "Up";
          vim = "K";
          focusAction = focus-window-up;
          moveAction = move-window-up;
          monitorFocusAction = focus-monitor-up;
          monitorMoveAction = move-column-to-monitor-up;
        }
        {
          arrow = "Right";
          vim = "L";
          focusAction = focus-column-right;
          moveAction = move-column-right;
          monitorFocusAction = focus-monitor-right;
          monitorMoveAction = move-column-to-monitor-right;
        }
      ];

      directionalBinds = mergeMany (
        map (direction:
          mkActionBinds direction.focusAction [
            "Mod+${direction.arrow}"
            "Mod+${direction.vim}"
          ]
          // mkActionBinds direction.moveAction [
            "Mod+Ctrl+${direction.arrow}"
            "Mod+Ctrl+${direction.vim}"
          ]
          // mkActionBinds direction.monitorFocusAction [
            "Mod+Shift+${direction.arrow}"
            "Mod+Shift+${direction.vim}"
          ]
          // mkActionBinds direction.monitorMoveAction [
            "Mod+Shift+Ctrl+${direction.arrow}"
            "Mod+Shift+Ctrl+${direction.vim}"
          ]
        ) directionDefs
      );

      mediaBinds = mkLockedSpawnShBinds spawn-sh [
        {
          key = "XF86AudioRaiseVolume";
          cmd = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0";
        }
        {
          key = "XF86AudioLowerVolume";
          cmd = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
        }
        {
          key = "XF86AudioMute";
          cmd = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        }
        {
          key = "XF86AudioMicMute";
          cmd = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
        }
        {
          key = "XF86AudioPlay";
          cmd = "playerctl play-pause";
        }
        {
          key = "XF86AudioStop";
          cmd = "playerctl stop";
        }
        {
          key = "XF86AudioPrev";
          cmd = "playerctl previous";
        }
        {
          key = "XF86AudioNext";
          cmd = "playerctl next";
        }
      ];

      brightnessBinds = {
        "XF86MonBrightnessUp" = {
          action = spawn "brightnessctl" "--class=backlight" "set" "+10%";
          allow-when-locked = true;
        };
        "XF86MonBrightnessDown" = {
          action = spawn "brightnessctl" "--class=backlight" "set" "10%-";
          allow-when-locked = true;
        };
      };

      workspaceBinds =
        mkActionBinds focus-workspace-down [
          "Mod+Page_Down"
          "Mod+U"
        ]
        // mkActionBinds focus-workspace-up [
          "Mod+Page_Up"
          "Mod+I"
        ]
        // mkActionBinds move-column-to-workspace-down [
          "Mod+Ctrl+Page_Down"
          "Mod+Ctrl+U"
        ]
        // mkActionBinds move-column-to-workspace-up [
          "Mod+Ctrl+Page_Up"
          "Mod+Ctrl+I"
        ]
        // mkActionBinds move-workspace-down [
          "Mod+Shift+Page_Down"
          "Mod+Shift+U"
        ]
        // mkActionBinds move-workspace-up [
          "Mod+Shift+Page_Up"
          "Mod+Shift+I"
        ]
        // mkWorkspaceBinds "focus-workspace" "Mod+"
        // mkWorkspaceBinds "move-column-to-workspace" "Mod+Ctrl+"
        // mkWorkspaceBinds "move-window-to-workspace" "Mod+Shift+";
    in
    {
      "Mod+E".action = spawn "thunar";
      "Mod+Shift+Slash".action = show-hotkey-overlay;
      "Mod+Shift+Return" = {
        action = spawn "foot";
        hotkey-overlay.title = "Open a Terminal: foot";
      };
      "Mod+P" = {
        action = spawn "fuzzel";
        hotkey-overlay.title = "Run an Application: fuzzel";
      };
      "Super+Alt+L" = {
        action = spawn "swaylock";
        hotkey-overlay.title = "Lock the Screen: swaylock";
      };

      "Mod+0" = {
        action = toggle-overview;
        repeat = false;
      };

      "Mod+Shift+C" = {
        action = close-window;
        repeat = false;
      };

      "Mod+Home".action = focus-column-first;
      "Mod+End".action = focus-column-last;
      "Mod+Ctrl+Home".action = move-column-to-first;
      "Mod+Ctrl+End".action = move-column-to-last;

      "Mod+Tab".action = focus-workspace-previous;

      "Mod+BracketLeft".action = consume-or-expel-window-left;
      "Mod+BracketRight".action = consume-or-expel-window-right;

      "Mod+Comma".action = consume-window-into-column;
      "Mod+Period".action = expel-window-from-column;

      "Mod+R".action = switch-preset-column-width;
      "Mod+Shift+R".action = switch-preset-window-height;
      "Mod+Ctrl+R".action = reset-window-height;
      "Mod+F".action = maximize-column;
      "Mod+Shift+F".action = fullscreen-window;
      "Mod+Ctrl+F".action = expand-column-to-available-width;

      "Mod+C".action = center-column;
      "Mod+Ctrl+C".action = center-visible-columns;

      "Mod+Minus".action = set-column-width "-10%";
      "Mod+Equal".action = set-column-width "+10%";

      "Mod+Shift+Minus".action = set-window-height "-10%";
      "Mod+Shift+Equal".action = set-window-height "+10%";

      "Mod+V".action = toggle-window-floating;
      "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;
      "Mod+W".action = toggle-column-tabbed-display;

      "Print".action.screenshot = {
        show-pointer = false;
      };
      "Alt+Print".action.screenshot-window = { };
      "Ctrl+Print".action.screenshot-screen = {
        show-pointer = false;
      };

      "Mod+Escape" = {
        action = toggle-keyboard-shortcuts-inhibit;
        allow-inhibiting = false;
      };

      "Mod+Shift+E".action = quit;
      "Ctrl+Alt+Delete".action = quit;

      "Alt+V".action = spawn "niri-clipboard" "menu";
      "Alt+Shift+V".action = spawn "niri-clipboard" "clear";

      "Mod+Shift+P".action = power-off-monitors;
    }
    // mediaBinds
    // brightnessBinds
    // directionalBinds
    // workspaceBinds;
}
