{
  palette,
  noctaliaIntegrations ? [ ],
}:
{
  config,
  lib,
  pkgs,
  inputs,
  hostFacts,
  ...
}:

let
  reducedMotion = palette.reducedMotion or false;
  logicalWidth = hostFacts.display.width / hostFacts.display.scale;
  logicalHeight = hostFacts.display.height / hostFacts.display.scale;
  wallpaperDir = pkgs.linkFarm "noctalia-cool-wallpapers" (
    map
      (name: {
        name = "wallpaper-${name}.png";
        path = ./resources/wallpaper/wallpaper-${name}.png;
      })
      [
        "002"
        "005"
        "008"
        "009"
        "011"
      ]
  );
  desktop = {
    primaryOutput = hostFacts.display.name;
  };
  reconcilePython = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  managedSettings = pkgs.writeText "noctalia-managed-settings.json" (
    builtins.toJSON config.programs.noctalia.settings
  );
  reconcileOverrides = pkgs.writeShellScript "reconcile-noctalia-overrides" ''
    exec ${reconcilePython}/bin/python3 ${./resources/reconcile-overrides.py} \
      --state ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/settings.toml"} \
      --managed ${managedSettings} \
      --backup-dir ${lib.escapeShellArg "${config.xdg.stateHome}/nix-dotfiles/ownership-backups"} \
      --require-no-noctalia
  '';

  defaultWallpaperPath = "${./resources/wallpaper/wallpaper-005.png}";

  distroLogo = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";

  lowBatterySuspend = pkgs.writeShellScript "noctalia-low-battery-suspend" ''
    set -euo pipefail
    threshold=5
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
    state_file="$state_dir/hook-battery-percent"
    percent="''${NOCTALIA_BATTERY_PERCENT:-}"
    battery_state="''${NOCTALIA_BATTERY_STATE:-unknown}"

    [[ "$percent" =~ ^[0-9]+$ ]] || exit 0

    mkdir -p "$state_dir"
    previous=""
    [[ -r "$state_file" ]] && previous="$(<"$state_file")"
    printf '%s\n' "$percent" > "$state_file"

    [[ "$battery_state" == "discharging" ]] || exit 0
    [[ "$previous" =~ ^[0-9]+$ ]] || exit 0

    if (( previous >= threshold && percent < threshold )); then
      ${pkgs.systemd}/bin/systemctl suspend
    fi
  '';

  # Use only the static variables explicitly exported to the user manager.
  # Never import the full Home Manager environment or interpolate secrets.
  safeSessionVariables =
    (import ../../lib/session-environment.nix { inherit lib; })
      config.systemd.user.sessionVariables;

in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  config = {
    # External dependencies declared by the enabled plugins that this machine
    # would otherwise be missing. Plugins never install their own dependencies
    # and just silently do nothing when one is absent -- no error, no hint.
    # Keep this in sync when adding or removing plugins; every entry maps to
    # one specific plugin.
    home.packages = with pkgs; [
      tmuxp # tmux-provider (tmux itself lives in tmux.nix)
      evtest # bongocat keyboard reactivity; mayon already belongs to input
    ];

    programs.noctalia = {
      enable = true;
      package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

      systemd.enable = true;
      customPalettes.One-Dark-Darker = {
        dark = {
          mPrimary = palette.blue;
          mOnPrimary = palette.black;
          mSecondary = palette.cyan;
          mOnSecondary = palette.black;
          mTertiary = palette.purple;
          mOnTertiary = palette.black;
          mError = palette.red;
          mOnError = palette.black;
          mSurface = palette.bg;
          mOnSurface = palette.brightFg;
          mSurfaceVariant = palette.surface;
          mOnSurfaceVariant = palette.fg;
          mOutline = palette.border;
          mShadow = palette.black;
          mHover = palette.selection;
          mOnHover = palette.brightFg;
          terminal = {
            background = palette.bg;
            foreground = palette.fg;
            cursor = palette.brightFg;
            cursorText = palette.bg;
            selectionBg = palette.selection;
            selectionFg = palette.brightFg;
            normal = {
              inherit (palette) black;
              inherit (palette) red;
              inherit (palette) green;
              inherit (palette) yellow;
              inherit (palette) blue;
              magenta = palette.purple;
              inherit (palette) cyan;
              white = palette.fg;
            };
            bright = {
              black = palette.border;
              inherit (palette) red;
              inherit (palette) green;
              inherit (palette) yellow;
              inherit (palette) blue;
              magenta = palette.purple;
              inherit (palette) cyan;
              white = palette.brightFg;
            };
          };
        };
      };

      settings =
        (import ./noctalia/bar.nix {
          inherit
            lib
            palette
            reducedMotion
            distroLogo
            pkgs
            hostFacts
            ;
        })
        // (import ./noctalia/plugins.nix { inherit inputs; })
        // {
          shell = {
            lang = "zh-CN";
            font_family = palette.fonts.sans;
            corner_radius_scale = 1.2;
            # One outer outline, quieter cards, and distinct input boundaries.
            button_borders = false;
            card_borders = false;
            input_borders = true;
            popup_borders = true;
            popup_shadows = true;
            # Native history owns collection and persistence; no parallel
            # cliphist watchers. The X11/Wayland bridge is a separate service.
            clipboard_enabled = true;
            show_location = true;
            # New in noctalia 5.2.1: readline-style editing (Ctrl+A/E/U/K) in
            # the shell's own text inputs.
            readline_shortcuts = true;

            animation = {
              enabled = !reducedMotion;
              speed = 1.0;
            };
            launch_apps_as_systemd_services = true;

            shadow = {
              direction = "down";
              alpha = 0.32;
            };

            panel = {
              # Reading surfaces stay opaque: Mango layer blur is deliberately
              # off, so transparency would expose sharp application text behind.
              transparency_mode = "solid";
              borders = true;
              border_color = "outline";
              border_width = 1;
              shadow = true;
              launcher_placement = "floating";
              clipboard_placement = "floating";
              control_center_placement = "floating";
              launcher_position = "center";
              control_center_position = "top_right";
              open_near_click_launcher = false;
              open_near_click_control_center = false;
              floating_offset = 16;
              # Hover/selection provides the row emphasis without a card per row.
              list_item_background = false;
              wallpaper_placement = "attached";
              session_placement = "attached";
            };

            launcher = {
              layout = "full";
              width = 680;
              search_position = "top";
              default_view = "recent";
              categories = true;
              category_icons_only = false;
              show_icons = true;
              compact = false;
              # List rows retain long names and descriptions; provider search,
              # pinned apps, categories and desktop actions remain available.
              app_grid = false;
              show_app_actions = true;
              sort_by_usage = true;
              pinned = [
                "kitty.desktop"
                "firefox.desktop"
                "thunar.desktop"
                "code.desktop"
              ];
              # calculator-plus is removed. The built-in provider has no enable
              # switch; exclude it from ordinary search. Its explicit /calc
              # prefix remains available (an empty prefix restores that default).
              providers = [
                {
                  name = "calculator";
                  global = false;
                }
              ];
            };

            screen_corners = {
              enabled = true;
              size = 12;
            };

            # Noctalia's built-in polkit authentication agent (the password
            # prompt for privileged actions). security.polkit.enable is already on
            # system-side and mango runs no other polkit agent, so letting Noctalia
            # be that agent does not conflict with anything.
            polkit_agent = true;
          };

          theme = {
            mode = "dark";
            shell_mode = "follow";
            source = "custom";
            custom_palette = "One-Dark-Darker";
            pure_black_dark = false;

            templates = {
              enable_builtin_templates = true;
              enable_community_templates = true;
              user = lib.optionalAttrs (builtins.elem "firefox" noctaliaIntegrations) {
                noctalia-firefox = {
                  input_path = "${../firefox/resources/noctalia-userChrome.css}";
                  output_path = "$XDG_CACHE_HOME/noctalia/firefox/userChrome.css";
                  post_hook = "${pkgs.writeShellScript "noctalia-firefox-theme-apply" ''
                    exec ${pkgs.python3}/bin/python3 ${../firefox/resources}/apply-noctalia-userChrome.py "''${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/firefox/userChrome.css"
                  ''}";
                  hook_async = false;
                };
              };
              builtin_ids = lib.optional (builtins.elem "btop" noctaliaIntegrations) "btop" ++ [
                "gtk3"
                "gtk4"
                "qt"
              ];
              community_ids = builtins.filter (id: builtins.elem id noctaliaIntegrations) [
                "obsidian"
                "vscode"
                "yazi"
                "zathura"
              ];
            };
          };

          desktop_widgets.enabled = false;

          wallpaper = {
            enabled = true;
            directory = "${wallpaperDir}";
            fill_mode = "crop";
            fill_color = "surface";
            transition_on_startup = !reducedMotion;
            transition = lib.optional (!reducedMotion) "fade";
            transition_duration = 450;
            default.path = defaultWallpaperPath;
            automation = {
              enabled = true;
              interval_seconds = 86400;
              order = "random";
              recursive = false;
            };
          };

          backdrop = {
            enabled = true;
            blur_intensity = 0.40;
            tint_intensity = 0.50;
          };

          audio = {
            enable_overdrive = true;
            enable_sounds = true;
          };

          brightness = {
            enable_ddcutil = true;
            minimum_brightness = 0.05;
            monitor.${desktop.primaryOutput}.backend = "backlight";
          };

          battery = {
            warning_threshold = 20;
          };

          # Put triggers in the bottom corners, away from the top bar's hover
          # area. The bottom edge is free while the dock is off.
          # action only accepts none / launcher / control_center / window_switcher
          # / command (hotCornerActionSelect in settings_registry.cpp); note it is
          # a free-form string in the schema, so a typo passes validation and then
          # silently does nothing at runtime.
          hot_corners = {
            enabled = true;
            delay_ms = 200; # dwell time, so a cursor merely passing by does not fire it
            bottom_left.action = "launcher";
            bottom_right.action = "none";
            top_left.action = "none";
            top_right.action = "none";
          };

          # force = false keeps the shift to night-time only instead of locking
          # the temperature all day.
          nightlight = {
            enabled = true;
            force = false;
            temperature_day = 6500;
            temperature_night = 4000;
          };

          weather = {
            enabled = true;
            unit = "metric";
            effects = !reducedMotion;
          };

          system.monitor = {
            enabled = true;
            gpu_poll_seconds = 0.0;
          };

          location = {
            auto_locate = true;
            address = "Jingkou Qu, China";
          };

          notification = {
            enable_daemon = true;
            position = "top_right";
            layer = "overlay";
            width = 380;
            offset_x = 14;
            offset_y = 62;
            max_visible = 3;
            border = true;
            border_width = 1;
            background_opacity = 0.97;
            # Keep transient messages on the output currently being used.
            follow_focused_output = true;
          };

          osd = {
            # Separate transient device feedback from notifications/control center.
            position = "bottom_center";
            orientation = "horizontal";
            offset_y = 28;
            hide_delay_ms = 1400;
            background_opacity = 0.97;
            follow_focused_output = true;
          };

          idle = {
            pre_action_fade_seconds = 3.0;
            behavior = {
              lock = {
                enabled = true;
                timeout = 900;
                action = "lock";
              };
              screen-off = {
                enabled = true;
                timeout = 1800;
                action = "screen_off";
              };
              suspend = {
                enabled = true;
                timeout = 3600;
                action = "lock_and_suspend";
              };
            };
          };

          hooks = {
            session_locked = [ "${pkgs.playerctl}/bin/playerctl pause" ];
            battery_discharging = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver";
            battery_charging = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
            battery_percentage_changed = "${lowBatterySuspend}";
          };

          # Off: the bar already carries a launcher and workspaces, so the dock is
          # a duplicate entry point. With it off every other dock.* key is
          # meaningless, hence the single line.
          dock.enabled = false;

          control_center = {
            sidebar = "full";
            # Direct volume/network/etc. entry keeps an icon rail; Home retains
            # its full labelled navigation and all tabs stay reachable.
            sidebar_section = "compact";
            width = 720;
            show_shortcut_labels = true;
          };

          lockscreen = {
            enabled = true;
            # Lock/unlock has its own effect pool; it does not inherit wallpaper.
            transition = lib.optional (!reducedMotion) "fade";
            transition_duration = 550;
            edge_smoothness = 0.3;
            blur_intensity = 0.40;
            tint_intensity = 0.60;
            blurred_desktop = false;
          };

          lockscreen_widgets = {
            enabled = true;
            widget_order = [
              "lockscreen-widget-clock"
              "lockscreen-widget-date"
              "lockscreen-login-box@${desktop.primaryOutput}"
            ];
            widget."lockscreen-login-box@${desktop.primaryOutput}" = {
              type = "login_box";
              output = desktop.primaryOutput;
              cx = logicalWidth / 2;
              cy = logicalHeight * 0.54;
              settings = {
                layout = "regular";
                show_media = false;
                show_weather = true;
                show_session_buttons = true;
                show_unlock_hint = true;
                show_caps_lock = true;
                show_keyboard_layout = true;
                background_color = "surface_variant";
                background_opacity = 1.0;
                background_radius = 16.0;
                input_radius = 10.0;
                input_opacity = 1.0;
              };
            };
            widget.lockscreen-widget-clock = {
              type = "clock";
              output = desktop.primaryOutput;
              cx = logicalWidth / 2;
              cy = logicalHeight * 0.24;
              box_width = 420.0;
              box_height = 110.0;
              settings = {
                format = "{:%H:%M}";
                font_family = palette.fonts.sans;
                center_text = true;
                background = false;
                color = "on_surface";
                shadow = true;
              };
            };
            widget.lockscreen-widget-date = {
              type = "clock";
              output = desktop.primaryOutput;
              cx = logicalWidth / 2;
              cy = logicalHeight * 0.325;
              box_width = 360.0;
              box_height = 32.0;
              settings = {
                format = "{:%m-%d  %A}";
                font_family = palette.fonts.sans;
                center_text = true;
                background = false;
                color = "on_surface";
                shadow = true;
              };
            };
          };
        };
    };

    # Keep Noctalia bound to the Mango session and enforce a bounded recovery
    # budget. The HM module owns the unit; these are field-level overrides.
    systemd.user.services.noctalia = {
      Unit = {
        PartOf = lib.mkForce [ "mango-session.target" ];
        After = lib.mkForce [ "mango-session.target" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStartPre = "${reconcileOverrides}";
        Restart = "on-failure";
        RestartSec = 2;
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") safeSessionVariables;
      };
      Install.WantedBy = lib.mkForce [ "mango-session.target" ];
    };
  };
}
