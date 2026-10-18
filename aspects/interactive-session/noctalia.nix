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
  wallpaperDir = "${./resources/wallpaper}";
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

  defaultWallpaperPath = "${./resources/wallpaper/wallpaper-009.png}";

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

  hyprlandEnabled = builtins.elem "hyprland-session.target" config.nixDotfiles.desktopSessionTargets;
  mangoPlugins = [
    "ezequiel/mango_layouts"
    "gambled23/mangowm-keymode"
  ];
  isMangoEntry = entry: builtins.any (id: entry == id || lib.hasPrefix "${id}:" entry) mangoPlugins;
  baseSettings = config.programs.noctalia.settings;
  # Share all public visual/application settings, but do not execute mmsg
  # plugins inside Hyprland. History, wallpaper and other state stay shared.
  hyprlandSettings = baseSettings // {
    plugins = baseSettings.plugins // {
      enabled = builtins.filter (entry: !isMangoEntry entry) baseSettings.plugins.enabled;
    };
    plugin_settings = builtins.removeAttrs baseSettings.plugin_settings mangoPlugins;
    widget = lib.filterAttrs (name: _: !isMangoEntry name) baseSettings.widget;
    bar = baseSettings.bar // {
      main = baseSettings.bar.main // {
        start = builtins.filter (entry: !isMangoEntry entry) baseSettings.bar.main.start;
        capsule_group = map (
          group:
          group
          // {
            members = builtins.filter (entry: !isMangoEntry entry) group.members;
          }
        ) baseSettings.bar.main.capsule_group;
      };
    };
  };
  hyprlandConfig = (pkgs.formats.toml { }).generate "noctalia-hyprland.toml" hyprlandSettings;
  # Noctalia's official CONFIG_HOME override appends /noctalia. Preserve every
  # HM-owned palette/template file beside the alternate config, without moving
  # the real XDG directories or splitting mutable application data.
  hyprlandConfigHome = pkgs.linkFarm "noctalia-hyprland-config-home" (
    lib.mapAttrsToList (name: file: {
      inherit name;
      path = if name == "noctalia/config.toml" then hyprlandConfig else file.source;
    }) (lib.filterAttrs (name: _: lib.hasPrefix "noctalia/" name) config.xdg.configFile)
  );
  sessionLauncher = pkgs.writeShellScript "noctalia-selected-session" ''
    case "''${XDG_CURRENT_DESKTOP:-}" in
      *Hyprland*|*hyprland*) export NOCTALIA_CONFIG_HOME=${hyprlandConfigHome} ;;
    esac
    exec ${lib.getExe config.programs.noctalia.package}
  '';

in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  config = {
    # The normal config directory autoloads every root-level TOML file.
    # Keep this variant outside it so Mango cannot accidentally merge it.
    xdg.configFile."noctalia-sessions/hyprland.toml" = lib.mkIf hyprlandEnabled {
      source = hyprlandConfig;
    };
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

      settings = {
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

        # Immutable plugin sources are pinned by flake.lock and available
        # offline. Git sources fetch during startup; update them through Nix.
        plugins = {
          # Enum since noctalia 5: all | official | none. A boolean is still
          # accepted but warns as deprecated at startup.
          auto_update = "none";

          source = [
            {
              name = "official";
              kind = "path";
              location = "${inputs.noctalia-plugins-official}";
              enabled = true;
            }
            {
              name = "community";
              kind = "path";
              # The pinned community-plugins now guards both of quill's
              # nextDueInMs() return paths, so the former local patch for its
              # index-service crash is gone.
              location = "${inputs.noctalia-plugins-community}";
              enabled = true;
            }
          ];

          # The pre-start ownership handoff removes only declared public
          # override paths, backing up those values before starting the writer.
          # Avoid compositor editor plugins that write the read-only HM config
          # and plugins whose external tools only support Hyprland.
          enabled = [
            "3ri4ng0ld/ip-monitor"
            "8bury/mini-docker"
            "cleboost/jetbrains-provider"
            "dunarand/tmux-provider"
            "noctalia/bongocat"
            "radimous/prismlauncher-instances"
            "rxtsel/portctl"
            "ezequiel/mango_layouts" # jq + mmsg
            # Markdown notes, todos and /nt launcher entry; optional AI uses OpenCode.
            "fel/quill"
            "gambled23/mangowm-keymode" # mmsg; shows the keymode SUPER,R enters

            # Notes/todo plugins were consolidated into Quill. OCR is provided
            # by the native Print bindings; its plugin had no configured entry.
            # The unused DeepSeek balance widget is disabled; its GUI data is
            # left in the runtime state, outside this store configuration.
          ];
        };

        # Plugin-level [[setting]] values belong here; [[widget.setting]]
        # values belong in widget."<plugin-id>:<entry-id>". Keep secrets in
        # runtime state or supported runtime files, never in Nix strings.
        plugin_settings = {
          # Noctalia injects generic panel settings for non-persistent entries.
          "ezequiel/mango_layouts" = {
            panel_placement = "attached";
            panel_position = "auto";
            panel_open_near_click = true;
          };
          # The CLI backend uses the installed OpenCode. Use a qualified model
          # ID so Quill does not prefix it with opencode-go/.
          "fel/quill" = {
            ai_backend = "opencode-cli";
            ai_model = "deepseek/deepseek-flash";
          };

        };

        bar.main = {
          position = "top";
          thickness = 38;
          reserve_space = true;
          auto_hide = false;
          layer = "top";
          panel_overlap = 1;
          background_opacity = 0.98;
          border = "outline";
          border_width = 1;
          radius = 12;
          margin_ends = 14;
          margin_edge = 8;
          padding = 8;
          widget_spacing = 8;
          shadow = true;
          contact_shadow = true;
          # Only semantic groups and the launcher get a persistent surface.
          # Group capsules are independent of this per-widget default.
          capsule = false;
          capsule_opacity = 0.96;
          capsule_fill = "surface_variant";
          capsule_radius = 8;
          capsule_thickness = 0.78;
          font_family = palette.fonts.sans;
          font_weight = 500;
          font_scale = 1.0;

          # Plugin widgets use manifest-id:entry-id. Everyday tools sit on the
          # left, the clock and cat in the center, system status on the right.
          start = [
            "launcher"
            "workspaces"
            # Mode feedback must stay visible even when tool drawers collapse.
            "gambled23/mangowm-keymode:mangowm-keymode"
            "group:dev"
            "group:panels"
            "group:media"
          ];
          center = [ "group:time" ];
          end = [
            "group:sys"
            "tray"
            "group:power"
            "control-center"
          ];

          capsule_group = [
            {
              id = "media";
              members = [ "media" ] ++ lib.optional (!reducedMotion) "audio_visualizer";
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "time";
              members = [ "clock" ] ++ lib.optional (!reducedMotion) "noctalia/bongocat:cat";
              accordion = false;
              fill = palette.deep;
              foreground = "on_surface";
              padding = 8.0;
              widget_spacing = 8;
            }
            {
              id = "panels";
              members = [
                "fel/quill:status" # Markdown notes + todos; replaced noctalia/notes
                "8bury/mini-docker:mini-docker" # Docker management
              ];
              # First member stays visible; hover reveals Docker, not a click toggle.
              accordion = true;
              accordion_direction = "end";
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "sys";
              members = [
                "network"
                "3ri4ng0ld/ip-monitor:widget"
                "bluetooth"
                "volume"
                "brightness"
                "notifications"
              ];
              accordion = false;
              fill = "surface";
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "power";
              members = [
                "sysmon"
                "power_profile"
                "caffeine"
                "battery"
              ];
              accordion = false;
              fill = "surface";
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "dev";
              members = [
                "ezequiel/mango_layouts:btn"
                "rxtsel/portctl:indicator" # inspect and kill port listeners
              ];
              # Keep layout as the anchor; /pan also exposes both tool panels.
              accordion = true;
              accordion_direction = "end";
              padding = 6.0;
              widget_spacing = 4;
            }
          ];
        };

        widget.launcher = {
          capsule = true;
          capsule_fill = "primary";
          color = "on_primary";
          icon_color = "on_primary";
        };

        widget."control-center" = {
          custom_image = distroLogo;
          custom_image_colorize = false;
        };
        widget."8bury/mini-docker:mini-docker" = {
          # An idle Docker engine is normal; only running containers need space.
          inactive_color = "on_surface_variant";
          status_mode = "running_only";
        };

        # Super+R enters resize mode; hide the badge in default mode.
        widget."gambled23/mangowm-keymode:mangowm-keymode".hide_on_default = true;
        widget."ezequiel/mango_layouts:btn".show_text = false;

        widget.battery.warning_color = palette.yellow;

        widget.media = {
          hide_when_no_media = true;
          max_length = 160;
          title_scroll = if reducedMotion then "none" else "on_hover";
        };

        # Keep DND visible even without unread items; right-click toggles it.
        widget.notifications.hide_when_no_unread = false;

        # A compact spectrum beside the existing media controls. PipeWire is
        # handled by Noctalia itself; no separate cava process is needed.
        widget.audio_visualizer = {
          width = 64;
          bands = 16;
          mirrored = true;
          centered = true;
          show_when_idle = false;
          color_1 = "primary";
          color_2 = "secondary";
        };

        widget."noctalia/bongocat:cat" = {
          executable_path = "${pkgs.evtest}/bin/evtest";
          input_devices = hostFacts.keyboardDevices;
          audio_spectrum = !reducedMotion;
          tappy_mode = !reducedMotion;
          rave_mode = false;
          use_mpris_filter = true;
        };

        widget.network = {
          # The glyph already says connected / disconnected / which kind. The
          # SSID next to it is ~110 physical pixels of a string that does not
          # change and cannot be acted on; it is still one hover away.
          show_label = false;
        };

        widget.sysmon = {
          # `highlightColor` defaults to ColorRole::Error (sysmon_widget.h:58),
          # so the CPU gauge is drawn in the palette's *error* colour at every
          # load -- a permanent red tick next to "1%". Red should mean
          # something is wrong. Primary is the accent the rest of the bar uses.
          highlight_color = "primary";
          # The label is as wide as the number in it, so the widget grew and
          # shrank between "1%" and "100%" and shoved its neighbours sideways
          # several times a second. Pin it to the width of the widest value.
          label_min_width = 34;
        };

        widget.clock = {
          format = "{:%m-%d  %H:%M}";
          vertical_format = "{:%H\n%M}";
          font_family = palette.fonts.mono;
        };

        widget.workspaces = {
          style = "regular";
          label_source = "id";
          show_labels = true;
          hide_when_empty = false;
          show_all_outputs = false;
          focused_output_only = true;
          active_pill_size = 1.5;
          inactive_pill_size = 1.0;
          focused_color = "primary";
          occupied_color = "surface_variant";
          empty_color = palette.deep;
          urgent_color = "error";
          font_scale = 1.0;
        };

        desktop_widgets.enabled = false;

        wallpaper = {
          enabled = true;
          directory = wallpaperDir;
          fill_mode = "crop";
          fill_color = "surface";
          transition_on_startup = !reducedMotion;
          transition = lib.optional (!reducedMotion) "fade";
          transition_duration = 450;
          default.path = defaultWallpaperPath;
          automation = {
            enabled = false;
            interval_seconds = 300;
            order = "random";
            recursive = true;
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

    # Keep Noctalia bound to selected compositor sessions and bound recovery
    # budget. The HM module owns the unit; these are field-level overrides.
    systemd.user.services.noctalia = {
      Unit = {
        PartOf = lib.mkForce config.nixDotfiles.desktopSessionTargets;
        After = lib.mkForce config.nixDotfiles.desktopSessionTargets;
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStart = lib.mkIf hyprlandEnabled (lib.mkForce "${sessionLauncher}");
        ExecStartPre = "${reconcileOverrides}";
        Restart = "on-failure";
        RestartSec = 2;
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") safeSessionVariables;
      };
      Install.WantedBy = lib.mkForce config.nixDotfiles.desktopSessionTargets;
    };
  };
}
