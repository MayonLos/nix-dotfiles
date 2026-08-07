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

          niri_overview_type_to_launch_enabled = true;

          # 启用 Noctalia 内置的 polkit 身份验证代理（提供特权操作的密码弹窗）。
          # 系统侧 security.polkit.enable=true 已开启，且 niri 下没有其它 polkit agent，
          # 所以由 Noctalia 来当这个 agent，不会冲突。
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
              "niri"
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

        plugins.source = [
          {
            name = "official";
            kind = "git";
            location = "https://github.com/noctalia-dev/official-plugins";
            enabled = false;
          }
          {
            name = "community";
            kind = "git";
            location = "https://github.com/noctalia-dev/community-plugins";
            enabled = false;
          }
        ];

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

          start = [
            "launcher"
            "workspaces"
            "media"
          ];
          center = [ ];
          end = [
            "network"
            "bluetooth"
            "volume"
            "brightness"
            "sysmon"
            "tray"
            "power_profile"
            "battery"
            "clock"
            "control-center"
          ];
        };

        widget."control-center" = {
          custom_image = distroLogo;
          custom_image_colorize = false;
        };
        widget.clock = {
          format = "{:%H:%M}";
          vertical_format = "{:%H\n%M}";
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

        # 夜间自动降色温。日落后从 6500K 渐变到 4000K；force=false 表示
        # 只在夜间生效而不是全天锁定。
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

        # 关掉：bar 上已经有 launcher 和 workspaces，dock 是重复入口。
        # 关掉后其余 dock.* 键全部无意义，所以只留这一行。
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
