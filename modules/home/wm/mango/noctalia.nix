{
  pkgs,
  inputs,
  ...
}:

let
  wallpaperDir = "${../../_assets/wallpaper}";
  desktop = import ../../../../lib/desktop.nix;
  defaultWallpaperPath = "${../../_assets/wallpaper/wallpaper-001.png}";

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

      systemd.enable = false;

      settings = {
        shell = {
          lang = "zh-CN";
          font_family = "Noto Sans CJK SC";
          corner_radius_scale = 1.0;
          # Native history owns collection and persistence; no parallel
          # cliphist watchers. The X11/Wayland bridge is a separate service.
          clipboard_enabled = true;
          show_location = true;
          # New in noctalia 5.2.1: readline-style editing (Ctrl+A/E/U/K) in
          # the shell's own text inputs.
          readline_shortcuts = true;

          animation = {
            enabled = true;
            speed = 0.95;
          };

          shadow = {
            direction = "down";
            alpha = 0.30;
          };

          panel = {
            transparency_mode = "glass";
            borders = true;
            shadow = true;
            launcher_placement = "floating";
            clipboard_placement = "floating";
            control_center_placement = "attached";
            wallpaper_placement = "attached";
            session_placement = "attached";
          };

          launcher = {
            categories = true;
            show_icons = true;
            compact = true;
            app_grid = true;
            sort_by_usage = true;
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
            size = 32;
          };

          # Noctalia's built-in polkit authentication agent (the password
          # prompt for privileged actions). security.polkit.enable is already on
          # system-side and mango runs no other polkit agent, so letting Noctalia
          # be that agent does not conflict with anything.
          polkit_agent = true;
        };

        theme = {
          mode = "auto";
          source = "builtin";
          builtin = "Tokyo-Night";

          templates = {
            enable_builtin_templates = true;
            enable_community_templates = true;
            # The builtin hook misses source_optional and tries to append to
            # our read-only config. Keep its template, but only reload Mango.
            # A fresh output path also leaves old, incompatible palettes out
            # of the new compositor's configuration.
            user.noctalia-mango = {
              input_path = "${inputs.noctalia}/assets/templates/mango/mango.conf";
              output_path = "$XDG_CONFIG_HOME/mango/noctalia-colors.conf";
              post_hook = "${pkgs.writeShellScript "noctalia-mango-theme-apply" ''
                ${
                  inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.mango
                }/bin/mmsg dispatch reload_config 2>/dev/null || true
              ''}";
            };
            user.noctalia-firefox = {
              input_path = "${../../programs/apps/_firefox/noctalia-userChrome.css}";
              output_path = "$XDG_CACHE_HOME/noctalia/firefox/userChrome.css";
              post_hook = "${pkgs.writeShellScript "noctalia-firefox-theme-apply" ''
                exec ${pkgs.python3}/bin/python3 ${../../programs/apps/_firefox}/apply-noctalia-userChrome.py "''${XDG_CACHE_HOME:-$HOME/.cache}/noctalia/firefox/userChrome.css"
              ''}";
              hook_async = false;
            };
            builtin_ids = [
              "btop"
              "gtk3"
              "gtk4"
              "qt"
            ];
            community_ids = [
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

          # GUI plugin toggles override this array in
          # ~/.local/state/noctalia/settings.toml. Remove its [plugins] table
          # and run `noctalia msg config-reload` to restore declarative control.
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
          # The CLI backend uses the installed OpenCode. Use a qualified model
          # ID so Quill does not prefix it with opencode-go/.
          "fel/quill" = {
            ai_backend = "opencode-cli";
            ai_model = "deepseek/deepseek-flash";
          };

          # Override the plugin's floating bottom-right panel with a bar panel.
          "ezequiel/mango_layouts" = {
            panel_placement = "attached";
            panel_position = "auto";
            panel_open_near_click = true;
          };
        };

        bar.main = {
          position = "top";
          thickness = 32;
          background_opacity = 0.92;
          radius = 12;
          margin_ends = 14;
          margin_edge = 8;
          padding = 6;
          widget_spacing = 8;
          shadow = true;
          contact_shadow = true;
          capsule = true;
          capsule_opacity = 0.96;

          # Plugin widgets use manifest-id:entry-id. Everyday tools sit on the
          # left, the clock and cat in the center, system status on the right.
          start = [
            "launcher"
            "workspaces"
            "group:media"
            "group:panels"
            "group:dev"
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
              members = [
                "media"
                "audio_visualizer"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 6;
            }
            {
              id = "time";
              members = [
                "clock"
                "noctalia/bongocat:cat"
              ];
              accordion = false;
              padding = 8.0;
              widget_spacing = 8;
            }
            {
              id = "panels";
              members = [
                "fel/quill:status" # Markdown notes + todos; replaced noctalia/notes
                "8bury/mini-docker:mini-docker" # Docker management
                "rxtsel/portctl:indicator" # inspect and kill port listeners
              ];
              accordion = false;
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
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "power";
              members = [
                "sysmon"
                "power_profile"
                "battery"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            {
              id = "dev";
              members = [
                "ezequiel/mango_layouts:btn"
                "gambled23/mangowm-keymode:mangowm-keymode"
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
          ];
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

        widget.media = {
          hide_when_no_media = true;
          max_length = 180;
          title_scroll = "on_hover";
        };

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
          input_devices = [
            "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
            "/dev/input/by-id/usb-ITE_Tech._Inc._ITE_Device_8176_-event-kbd"
          ];
          audio_spectrum = true;
          tappy_mode = true;
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
        };

        widget.workspaces = {
          # mango always defines all `tag_num` tags, so the bar would otherwise
          # show 1-9 permanently. This collapses a tag out of the row once it
          # holds no windows; the active tag stays visible even when empty.
          hide_when_empty = true;
        };

        desktop_widgets.enabled = false;

        wallpaper = {
          enabled = true;
          directory = wallpaperDir;
          fill_mode = "crop";
          fill_color = "surface";
          transition_on_startup = true;
          transition = [
            "fade"
            "wipe"
            "disc"
            "stripes"
            "zoom"
            "honeycomb"
          ];
          transition_duration = 1200;
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
          blur_intensity = 0.55;
          tint_intensity = 0.65;
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
          bottom_right.action = "control_center";
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
          effects = true;
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
          layer = "overlay";
          background_opacity = 0.95;
          # New in 5.2.1. No-op on the single panel, correct once a second
          # output is attached.
          follow_focused_output = true;
        };

        osd = {
          position = "top_right";
          background_opacity = 0.95;
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

        lockscreen = {
          enabled = true;
          blur_intensity = 0.5;
          tint_intensity = 0.3;
          blurred_desktop = true;
        };
      };
    };
  };
}
