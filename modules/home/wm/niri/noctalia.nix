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
    # 已启用插件声明的外部依赖里，本机缺的那些。插件不会自己装依赖，
    # 缺了就是静默不工作（不报错、不提示），所以在这里补齐。
    # 增删插件时记得同步这个列表——每一项都对应一个具体的插件。
    home.packages = with pkgs; [
      tmuxp # tmux-provider（tmux 本体在 tmux.nix）
      pulseaudio # 只为 pactl 这个 CLI，audio-switcher 用；
      # 音频服务端仍是 pipewire，这里不会顶替它
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

        # kind = "path" 而不是 "git"：noctalia 把 Path 源当成只读的不可变目录
        # （config_types.h 的注释原话就是 "e.g. a Nix store path"），启动时直接
        # 读 location，不 clone、不联网、update/auto_update 都是 no-op。
        #
        # 这一点对这台机器是硬要求：git 源在启动阶段 clone，github 不通时会卡满
        # 超时然后段错误，niri 自启的 noctalia 直接死掉——这也是这两个源之前
        # 一直 enabled = false 的原因。走 store path 后崩溃面消失，版本也锁进了
        # flake.lock，更新统一走 nix flake update。
        plugins = {
          auto_update = false;

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
          ];

          # ⚠️ 这个列表会被运行时覆盖层盖掉。
          # 在 Noctalia 设置界面里开关插件，会把整份 enabled 数组写进
          # ~/.local/state/noctalia/settings.toml，而那份优先级更高——也就是说
          # GUI 一旦动过，这里写什么都不再生效。想让这里重新说了算，就把覆盖层
          # 里的 [plugins] 段删掉再 `noctalia msg config-reload`。
          # 反过来，想把 GUI 里试出来的结果固化回来，用
          # `noctalia config export merged` 读出实际值抄进来。
          #
          # 刻意排除的：battery-threshold（要 sudo/groupadd/usermod 改系统权限）、
          # niri-animations（会写只读的 niri HM 符号链接）、screen-toolkit /
          # color_picker / keybind-cheatsheet（依赖 hyprpicker、hyprctl，
          # Hyprland 专用）、translator（走 Google 翻译，本地不通）。
          enabled = [
            "3ri4ng0ld/ip-monitor"
            "8bury/mini-docker"
            "blackbartblues/audio-switcher"
            "cleboost/jetbrains-provider"
            "dunarand/tmux-provider"
            "nightwatch75/todo"
            "noctalia/kaomoji"
            "noctalia/notes"
            "radimous/prismlauncher-instances"
            "rxtsel/portctl"
            "salemsayed/niri-active-workspace"
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

          # 插件 widget 在 bar 里的写法是 `<plugin-id>:<entry-id>`：
          # widget_factory.cpp 直接把这个字符串丢给 PluginRegistry::resolve()，
          # 而 resolve() 按第一个冒号切成 manifest.id + entry.id
          # (plugin_registry.cpp:20 `manifest->id + ":" + entry->id`)。
          # entry-id 来自各插件 plugin.toml 的 [[widget]] id，不是插件名，
          # 常见的 entry-id 是 "bar"、"widget"、"status"，多个插件重名很正常。
          #
          # 左边放上下文和常用工具，中间时钟，右边系统状态。
          #
          # panels 组整组放在 start：这四个都是「点一下开面板」的工具，摆在左边
          # 顺手，而且 start 是左对齐、向右生长的通道，空间充裕——不像 end 右对齐、
          # 溢出时会从最左端开始裁（之前 notes 看不见就是这么来的）。
          start = [
            "launcher"
            "salemsayed/niri-active-workspace:active-workspace"
            "media"
            "group:panels"
          ];
          center = [ "clock" ];
          end = [
            "group:sys"
            "sysmon"
            "tray"
            "power_profile"
            "battery"
            "control-center"
          ];

          capsule_group = [
            # 常用工具，全部常驻展开（不折叠）
            {
              id = "panels";
              members = [
                "noctalia/notes:notes" # 侧栏速记
                "nightwatch75/todo:todo" # 任务清单
                "8bury/mini-docker:mini-docker" # Docker 管理
                "rxtsel/portctl:indicator" # 端口查杀
              ];
              accordion = false;
              padding = 6.0;
              widget_spacing = 4;
            }
            # 常驻扫视的系统状态，始终展开
            {
              id = "sys";
              members = [
                "network"
                "3ri4ng0ld/ip-monitor:widget"
                "bluetooth"
                "blackbartblues/audio-switcher:widget"
                "volume"
                "brightness"
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

        # 屏幕角落触发。用底边两角而不是顶边——bar 在顶部（margin_edge 6、
        # margin_ends 8），顶角和 bar 的悬停区挨得太近容易误触；dock 关掉之后
        # 底边完全空出来了，正好用。
        # action 合法值只有 none / launcher / control_center / window_switcher /
        # command 这五个（settings_registry.cpp 的 hotCornerActionSelect）；
        # 注意它在 schema 里是自由字符串，写错了验证器不报错、运行时静默失效。
        hot_corners = {
          enabled = true;
          delay_ms = 200; # 停留 200ms 才触发，避免鼠标划过就弹
          bottom_left.action = "launcher";
          bottom_right.action = "control_center";
          top_left.action = "none";
          top_right.action = "none";
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
