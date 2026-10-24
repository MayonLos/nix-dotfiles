{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  profile = config.home.profileDirectory;
  target = "xorg-session.target";
  px = n: builtins.floor (n * hostFacts.display.x11Dpi / 96.0 + 0.5);
  dmenuPackage = import ./dmenu/package.nix { inherit pkgs; };

  # One menu renderer for launcher, desktop controls and Dunst actions.
  # Font sizes are points; Xft supplies the host DPI without scaling twice.
  dmenu = pkgs.writeShellApplication {
    name = "xorg-dmenu";
    text = ''
      exec ${dmenuPackage}/bin/dmenu -i -l 8 -c \
        -z ${toString (px 460)} -h ${toString (px 32)} \
        -bw ${toString (px 1)} -ip ${toString (px 12)} \
        -bc ${lib.escapeShellArg palette.selection} \
        -fn ${lib.escapeShellArg "${palette.fonts.sans}:size=10.5"} \
        -nb ${lib.escapeShellArg palette.bg} -nf ${lib.escapeShellArg palette.brightFg} \
        -sb ${lib.escapeShellArg palette.selection} -sf ${lib.escapeShellArg palette.blue} \
        "$@"
    '';
  };
  launcher = pkgs.writeShellApplication {
    name = "xorg-launcher";
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles"
      mkdir -p -- "$state_dir"
      # Delegate desktop Exec/Terminal parsing and usage ordering to j4.
      # No --wait-on daemon; this process exists only while choosing an app.
      exec ${pkgs.j4-dmenu-desktop}/bin/j4-dmenu-desktop \
        --dmenu=${lib.escapeShellArg "${dmenu}/bin/xorg-dmenu -p 应用"} \
        --term-mode=kitty --term=${pkgs.kitty}/bin/kitty --no-generic \
        --log-level=WARNING --use-xdg-de \
        --usage-log="$state_dir/dmenu-usage"
    '';
  };

  # dwm's BAR_STATUS2D_PATCH interprets only our fixed ^c#RRGGBB^ / ^d^ codes.
  # Values come from numeric/local state, never arbitrary external labels.
  # Keep the bar quiet: no machine identifiers, network names, or CPU polling.
  status = pkgs.writeShellApplication {
    name = "xorg-status";
    text = ''
      trap 'exit 0' INT TERM
      previous=""
      while :; do
        volume="^c${palette.muted}^^d^ --"
        raw_volume="$(${pkgs.coreutils}/bin/timeout 2 ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
        if [[ "$raw_volume" == *"[MUTED]"* ]]; then
          volume="^c${palette.muted}^ muted^d^"
        elif [[ "$raw_volume" =~ ^Volume:\ ([0-9]+)[.]([0-9][0-9]) ]]; then
          percent=$((10#''${BASH_REMATCH[1]} * 100 + 10#''${BASH_REMATCH[2]}))
          volume="^c${palette.muted}^^d^ $percent%"
        fi

        batteries=""
        # Discover batteries by their sysfs type; BAT0 is not universal, and
        # removable/secondary batteries may appear during the session.
        for supply in /sys/class/power_supply/*; do
          [[ -r "$supply/type" && -r "$supply/capacity" ]] || continue
          [[ "$(< "$supply/type")" == "Battery" ]] || continue
          capacity="$(< "$supply/capacity")" || continue
          [[ "$capacity" =~ ^[0-9]{1,3}$ ]] || continue
          [[ "$capacity" -le 100 ]] || continue
          state=""
          battery_color="${palette.fg}"
          [[ "$capacity" -gt 20 ]] || battery_color="${palette.red}"
          case "$capacity" in
            100|9[0-9]) battery_icon="" ;;
            [6-8][0-9]) battery_icon="" ;;
            [3-5][0-9]) battery_icon="" ;;
            [12][0-9]) battery_icon="" ;;
            *) battery_icon="" ;;
          esac
          if [[ -r "$supply/status" ]]; then
            case "$(< "$supply/status")" in
              Charging) state="+"; battery_color="${palette.green}" ;;
              Discharging) state="-" ;;
            esac
          fi
          batteries+=" ^c${palette.selection}^·^d^ ^c$battery_color^$battery_icon $capacity%$state^d^"
        done

        clock="$(LC_TIME=C ${pkgs.coreutils}/bin/date '+%m-%d  %H:%M')"
        current=" $volume$batteries ^c${palette.selection}^·^d^ ^c${palette.blue}^^d^ ^c${palette.brightFg}^$clock^d^ "
        if [[ "$current" != "$previous" ]]; then
          ${pkgs.xsetroot}/bin/xsetroot -name "$current"
          previous="$current"
        fi
        ${pkgs.coreutils}/bin/sleep 8
      done
    '';
  };

  helpText = pkgs.writeText "xorg-session-help.txt" ''
    dwm · Xorg
    ────────────────────────────────────────────────────────────

    状态栏
      左侧标签切换工作区；窗口标题显示当前焦点。
      点击右侧状态区域打开桌面控制菜单。
      扬声器图标是输出音量；电池后的 + / - 表示充电 / 放电。
      充电显示绿色；未充电且电量不超过 20% 显示红色。
      多电池分别显示；无电池设备省略电池区域。

    桌面控制菜单
      应用启动器、音量、网络、蓝牙和剪贴板。
      桌面合成可随时开关，控制 Picom 的浮窗阴影、圆角与防撕裂。
      dmenu 输入筛选，方向键选择，Enter 确认，Escape 取消。
      锁屏立即锁定；退出需要再次确认。

    窗口操作
      Super + Return / B / E 打开终端 / 浏览器 / 文件管理器。
      Alt + Space 启动器；Super + P 控制菜单；Super + F1 本帮助。
      Super + J / K 前后切窗，H / L 调整主区比例，Q 关闭窗口。
      Super + T 平铺，M 单窗口布局，Shift + T 自由布局；F 全屏。
      Super + Ctrl + Return 提升到主区，I / U 增减主区窗口数。
      Super + 逗号 / 句号 切换显示器，加 Shift 移动窗口。
      Super + 鼠标左键拖动窗口。
      Super + 鼠标右键调整窗口大小。
      Super + Shift + Space 切换窗口浮动。
      Super + 1…9 切换标签。
      Super + Shift + 1…9 将窗口移到标签。
      Super + Shift + Return 暂存终端，Super + Alt + E 暂存 Yazi。
      Print 区域截图，Ctrl + Print 全桌截图，复制到剪贴板。

    QQ / 腾讯会议
      从托盘恢复窗口；需要自由摆放时切换浮动。
      会议共享使用应用自身的 Xorg 屏幕 / 窗口选择器。

    使用方向键 / PageUp / PageDown 滚动；按 q 关闭帮助。
  '';

  help = pkgs.writeShellApplication {
    name = "xorg-session-help";
    text = ''
      export LESSSECURE=1
      exec ${pkgs.kitty}/bin/kitty --class xorg-help \
        --title 'dwm · 快捷键与桌面帮助' \
        ${pkgs.less}/bin/less --ignore-case -- ${helpText}
    '';
  };

  effects = pkgs.writeShellApplication {
    name = "xorg-effects";
    text = ''
      if [[ "''${XDG_CURRENT_DESKTOP:-}" != dwm ]] || \
        ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet ${target}; then
        echo 'xorg-effects: an active dwm session is required' >&2
        exit 1
      fi
      if ${pkgs.systemd}/bin/systemctl --user is-active --quiet picom.service; then
        exec ${pkgs.systemd}/bin/systemctl --user stop picom.service
      else
        exec ${pkgs.systemd}/bin/systemctl --user start picom.service
      fi
    '';
  };

  menu = pkgs.writeShellApplication {
    name = "xorg-session-menu";
    text = ''
      effects_label='开启桌面合成'
      if ${pkgs.systemd}/bin/systemctl --user is-active --quiet picom.service; then
        effects_label='关闭桌面合成'
      fi
      # dmenu returns text, including arbitrary typed input. Dispatch only
      # exact entries from this menu; never evaluate its output as a command.
      choice="$(printf '%s\n' \
        '应用启动器' '音量设置' '网络设置' '蓝牙设备' '剪贴板历史' \
        "$effects_label" '快捷键与帮助' '锁屏' '退出 dwm 会话' | \
        ${dmenu}/bin/xorg-dmenu -p '桌面')" || exit 0
      case "$choice" in
        '应用启动器') exec ${launcher}/bin/xorg-launcher ;;
        '音量设置') exec ${pkgs.pavucontrol}/bin/pavucontrol ;;
        '网络设置') exec ${pkgs.networkmanagerapplet}/bin/nm-connection-editor ;;
        '蓝牙设备') exec ${pkgs.blueman}/bin/blueman-manager ;;
        '剪贴板历史') exec ${pkgs.copyq}/bin/copyq toggle ;;
        "$effects_label") exec ${effects}/bin/xorg-effects ;;
        '快捷键与帮助') exec ${help}/bin/xorg-session-help ;;
        '锁屏') exec ${lib.escapeShellArg "${profile}/bin/xorg-lock"} ;;
        '退出 dwm 会话')
          confirm="$(printf '%s\n' '返回桌面' '退出当前 dwm 会话' | \
            ${dmenu}/bin/xorg-dmenu -l 2 -p '请先保存工作 · 确认退出')" || exit 0
          if [[ "$confirm" == '退出当前 dwm 会话' ]]; then
            exec ${lib.escapeShellArg "${profile}/bin/xorg-session-exit"}
          fi
          ;;
      esac
    '';
  };
in
{
  home.packages = [
    dmenu
    launcher
    status
    menu
    help
    effects
  ];

  systemd.user.services.xorg-status = {
    Unit = {
      Description = "Native dwm bar status";
      PartOf = [ target ];
      After = [ target ];
      Requisite = [ target ];
      ConditionEnvironment = "XDG_CURRENT_DESKTOP=dwm";
    };
    Service = {
      Type = "simple";
      ExecStart = "${status}/bin/xorg-status";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ target ];
  };
}
