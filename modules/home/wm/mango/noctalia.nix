{
  pkgs,
  inputs,
  ...
}:

let
  wallpaperDir = "${../../_assets/wallpaper}";
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
          clipboard_enabled = true;
          show_location = true;

          animation = {
            enabled = true;
            speed = 0.95;
          };

          shadow = {
            direction = "down";
            alpha = 0.55;
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
            builtin_ids = [
              "btop"
              "cava"
              "foot"
              "gtk3"
              "gtk4"
              "mango"
              "qt"
            ];
            community_ids = [
              "obsidian"
              "vscode"
              "yazi"
              "zathura"
              "zen-browser"
            ];
          };
        };

        # kind = "path" rather than "git": noctalia treats a Path source as a
        # read-only immutable directory (config_types.h says so verbatim, "e.g.
        # a Nix store path"), reads location directly at startup, and never
        # clones or touches the network -- update/auto_update are no-ops.
        #
        # That is a hard requirement on this machine: a git source clones during
        # startup, and when github is unreachable it burns the whole timeout and
        # then segfaults, taking down the noctalia that mango autostarts -- which
        # is why both sources used to sit at enabled = false. Store paths remove
        # that failure mode and pin the versions in flake.lock; updates go
        # through nix flake update like everything else.
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
              location = "${inputs.noctalia-plugins-community}";
              enabled = true;
            }
            # No local source. `_plugins/ask` (an LLM chat panel) was the only
            # thing in it and was removed on 2026-09-18; a path source pointing
            # at a directory that no longer exists fails evaluation, so the
            # whole block goes with it. To add one back: create
            # `_plugins/<name>/plugin.toml` and restore this entry -- with no
            # catalog.toml a path source just scans the directory
            # (plugin_catalog.cpp:272).
          ];

          # WARNING: this list is shadowed by the runtime override layer.
          # Toggling a plugin in Noctalia's settings UI writes the entire enabled
          # array into ~/.local/state/noctalia/settings.toml, which takes
          # priority -- once the GUI has touched it, nothing written here has any
          # effect. To hand control back, drop the [plugins] section from the
          # override layer and run `noctalia msg config-reload`. The other way
          # round, `noctalia config export merged` prints the effective values so
          # whatever you settled on in the GUI can be copied back here.
          #
          # Deliberately excluded: battery-threshold (needs sudo/groupadd/usermod
          # to change system permissions), compositor animations (writes to the
          # read-only HM symlink), screen-toolkit / color_picker /
          # keybind-cheatsheet (depend on hyprpicker and hyprctl, Hyprland only),
          # translator (goes through Google Translate, unreachable here).
          enabled = [
            "3ri4ng0ld/ip-monitor"
            "8bury/mini-docker"
            "cleboost/jetbrains-provider"
            "dunarand/tmux-provider"
            "nightwatch75/todo"
            "noctalia/kaomoji"
            "noctalia/notes"
            "radimous/prismlauncher-instances"
            "rxtsel/portctl"
            "whyoolw/sharednd"
          ];
        };

        bar.main = {
          position = "top";
          thickness = 30;
          background_opacity = 0.88;
          radius = 16;
          margin_ends = 8;
          margin_edge = 6;
          padding = 8;
          widget_spacing = 6;
          shadow = true;
          contact_shadow = true;
          capsule = true;
          capsule_opacity = 0.96;

          # A plugin widget is spelled `<plugin-id>:<entry-id>` in the bar:
          # widget_factory.cpp hands the string straight to
          # PluginRegistry::resolve(), which splits it on the first colon into
          # manifest.id + entry.id (plugin_registry.cpp:20
          # `manifest->id + ":" + entry->id`). The entry-id comes from the
          # [[widget]] id in each plugin's plugin.toml, not from the plugin name;
          # "bar", "widget" and "status" are common, and collisions across
          # plugins are perfectly normal.
          #
          # Context and everyday tools on the left, clock in the center, system
          # status on the right.
          #
          # The panels group goes into start as a whole: all four are "click to
          # open a panel" tools, handy on the left, and start is left-aligned and
          # grows rightwards with room to spare -- unlike end, which is
          # right-aligned and clips from its leftmost item on overflow (that is
          # how notes went missing before).
          start = [
            "launcher"
            "workspaces"
            "media"
            "group:panels"
          ];
          center = [ "clock" ];
          # Four capsules on each side. `end` used to carry six -- the sys
          # group plus sysmon, tray, power_profile, battery and control-center
          # each in a capsule of its own, against four on the left, which made
          # the right half read as a row of loose pills rather than as groups.
          # sysmon, power_profile and battery are one subject (how much the
          # machine is working and what it is running on), so they became one.
          end = [
            "group:sys"
            "tray"
            "group:power"
            "control-center"
          ];

          capsule_group = [
            {
              id = "panels";
              members = [
                "noctalia/notes:notes" # sidebar scratchpad
                "nightwatch75/todo:todo" # task list
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
          ];
        };

        widget."control-center" = {
          custom_image = distroLogo;
          custom_image_colorize = false;
        };
        # A plugin's bar widget takes its settings from the same `widget.<id>`
        # table as a builtin one, keyed by the full `<plugin-id>:<entry-id>`
        # spelling (config_export.cpp:367). NOT `plugin_settings.*` -- that
        # table is for keys a plugin declares as a top-level [[setting]], and
        # `inactive_color` is a [[widget.setting]], i.e. it belongs to the
        # widget entry. Putting it in plugin_settings parses, exports, and does
        # nothing; measured before this comment existed.
        widget."8bury/mini-docker:mini-docker" = {
          # widget.luau:46 fills the status dot with
          # `runningCount > 0 and active_color or inactive_color`, and
          # inactive_color defaults to "error" -- so a red dot sits in the bar
          # whenever no container is running, which on a laptop is nearly
          # always. Docker itself is fine (it is rootless here, so the unit to
          # ask about is `systemctl --user is-active docker`, which says
          # active); "nothing running" is not a fault. Same correction as
          # widget.sysmon below: red is for things that are wrong.
          inactive_color = "on_surface_variant";
          # The count is 0 unless something is actually running, and a widget
          # whose only state is "0" is a widget that says nothing. This hides
          # the glyph, the count and the dot entirely until a container comes
          # up, at which point it appears with a real number in it.
          status_mode = "running_only";
        };

        # "暂无播放内容" is not information. The widget sat there at full width
        # announcing that nothing was playing, which is most of the time.
        widget.media.hide_when_no_media = true;

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
          format = "{:%H:%M}";
          vertical_format = "{:%H\n%M}";
        };

        widget.workspaces = {
          # mango always defines all `tag_num` tags, so the bar would otherwise
          # show 1-9 permanently. This collapses a tag out of the row once it
          # holds no windows; the active tag stays visible even when empty.
          hide_when_empty = true;
        };

        wallpaper = {
          enabled = true;
          directory = wallpaperDir;
          fill_mode = "stretch";
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
          monitor."eDP-1".backend = "backlight";
        };

        battery = {
          warning_threshold = 20;
        };

        # Screen corner triggers, on the bottom corners rather than the top
        # ones -- the bar sits at the top (margin_edge 6, margin_ends 8) and the
        # top corners are close enough to its hover area to fire by accident,
        # while the bottom edge is completely free now that the dock is off.
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
        };

        osd = {
          position = "top_right";
          background_opacity = 0.95;
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
