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

  # Rasi px dimensions are device pixels; font points already follow Xft DPI.
  renderTheme =
    path:
    let
      themed =
        builtins.replaceStrings
          [
            "@WIDTH@"
            "#1e2228"
            "#181b20"
            "#272c33"
            "#323843"
            "#abb2bf"
            "#d7dae0"
            "#828a95"
            "#61afef"
            "#2b3038"
            "Maple Mono NF CN 12"
            "Maple Mono NF CN 9"
          ]
          [
            "560"
            palette.bg
            palette.deep
            palette.surface
            palette.selection
            palette.fg
            palette.brightFg
            palette.muted
            palette.blue
            palette.surface
            "${palette.fonts.mono} 10.5"
            "${palette.fonts.mono} 9"
          ]
          (builtins.readFile path);
    in
    lib.concatMapStrings (
      part: if builtins.isList part then "${toString (px (lib.toInt (builtins.head part)))}px" else part
    ) (builtins.split "([0-9]+)px" themed);
  launcherText = renderTheme ./resources/rofi-launcher.rasi;
  launcherTheme = pkgs.writeText "rofi-launcher.rasi" launcherText;
  powerTheme = pkgs.writeText "rofi-power.rasi" (
    launcherText + "\n" + renderTheme ./resources/rofi-power.rasi
  );
  powerEntries = builtins.fromJSON (builtins.readFile ./resources/power-menu.json);
  powerIcons = pkgs.linkFarm "xorg-power-icons" (
    map (entry: {
      name = "${entry.label}.svg";
      path = pkgs.writeText "${entry.label}.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${palette.muted}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="${entry.path}"/></svg>
      '';
    }) powerEntries
  );
  powerRows = lib.concatMapStringsSep "\n" (
    entry: "${entry.label}\\0icon\\x1f${powerIcons}/${entry.label}.svg"
  ) powerEntries;
  copyqMode = pkgs.writeShellApplication {
    name = "xorg-rofi-copyq";
    runtimeInputs = [
      pkgs.python3
      pkgs.copyq
    ];
    text = ''
      export XORG_COPYQ=${lib.escapeShellArg "${pkgs.copyq}/bin/copyq"}
      exec ${pkgs.python3}/bin/python3 ${./resources/rofi-copyq.py}
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "xorg-launcher";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
      mode="''${1:-Apps}"
      case "$mode" in
        Apps) mode=drun; shift || true ;;
        Run) mode=run; shift ;;
        Windows) mode=window; shift ;;
        Clipboard) shift ;;
        *) mode=drun ;;
      esac
      exec ${pkgs.rofi}/bin/rofi -dpi ${toString hostFacts.display.x11Dpi} -p '❯' \
        -show "$mode" \
        -modi ${lib.escapeShellArg "drun,run,window,Clipboard:${copyqMode}/bin/xorg-rofi-copyq"} \
        -display-drun Apps -display-run Run -display-window Windows \
        -kb-mode-next 'Tab,Control+Tab' -kb-element-next "" \
        -show-icons -icon-theme ${lib.escapeShellArg palette.iconTheme} \
        -matching fuzzy \
        -theme ${launcherTheme} \
        "$@"
    '';
  };

  notificationMenu = pkgs.writeShellApplication {
    name = "xorg-rofi-dmenu";
    runtimeInputs = [ pkgs.rofi ];
    text = ''
      exec ${pkgs.rofi}/bin/rofi -dpi ${toString hostFacts.display.x11Dpi} -dmenu -i -no-custom -theme ${launcherTheme} "$@"
    '';
  };

  statusProgram = pkgs.writeText "xorg-status.py" (builtins.readFile ./resources/status.py);
  status = pkgs.writeShellApplication {
    name = "xorg-status";
    runtimeInputs = [
      pkgs.python3
      pkgs.xprop
      pkgs.xsetroot
      pkgs.wireplumber
      pkgs.fcitx5
      config.services.dunst.package
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${statusProgram} \
        --blue ${lib.escapeShellArg palette.blue} \
        --cyan ${lib.escapeShellArg palette.cyan} \
        --green ${lib.escapeShellArg palette.green} \
        --red ${lib.escapeShellArg palette.red} \
        --muted ${lib.escapeShellArg palette.muted} \
        --fg ${lib.escapeShellArg palette.fg}
    '';
  };

  keybindings = builtins.fromJSON (builtins.readFile ./dwm/keybindings.json);
  helpRows = lib.concatMapStringsSep "\n" (
    binding:
    let
      label =
        if (binding.label or "") != "" then
          binding.label
        else if (binding.kind or "") == "command" then
          lib.concatStringsSep " " binding.arg
        else
          "";
    in
    if label == "" then "" else "  ${binding.mods} + ${binding.key}    ${label}"
  ) keybindings;
  helpText = pkgs.writeText "xorg-session-help.txt" ''
    dwm · Xorg
    ────────────────────────────────────────────────────────────

    状态栏：左侧标签与布局，中央时钟，右侧资源、设备与输入状态。
    电池“养护”表示 Legion conservation_mode 已启用；中/英仅表示 Fcitx 引擎激活状态，
    无法从 fcitx5-remote 推断 Rime 内部的中英子模式。

    启动器与会话菜单的快捷键列在下表；Apps / Run / Windows / Clipboard 可用 Tab 切换。
    电源菜单中的退出、挂起、重启和关机需再次确认；Lock 立即执行。
    Esc 关闭菜单。

    快捷键（由 dwm/keybindings.json 生成）
    ${helpRows}

    QQ / 腾讯会议
      从托盘恢复窗口；需要自由摆放时切换浮动。
      会议共享使用应用自身的 Xorg 屏幕 / 窗口选择器。

    使用方向键 / PageUp / PageDown 滚动；按 q 关闭帮助。
  '';

  help = pkgs.writeShellApplication {
    name = "xorg-session-help";
    runtimeInputs = [
      pkgs.kitty
      pkgs.less
    ];
    text = ''
      export LESSSECURE=1
      exec ${pkgs.kitty}/bin/kitty --class xorg-help \
        --title 'dwm · 快捷键与桌面帮助' \
        ${pkgs.less}/bin/less --ignore-case -- ${helpText}
    '';
  };

  effects = pkgs.writeShellApplication {
    name = "xorg-effects";
    runtimeInputs = [ pkgs.systemd ];
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

  powerMenu = pkgs.writeShellApplication {
    name = "xorg-power-menu";
    runtimeInputs = [
      pkgs.rofi
      pkgs.systemd
    ];
    text = ''
      if [[ "''${XDG_CURRENT_DESKTOP:-}" != dwm ]] || \
        ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet ${target}; then
        echo 'xorg-session-menu: an active dwm session is required' >&2
        exit 1
      fi

      choice="$(printf '%b\n' ${lib.escapeShellArg powerRows} | \
        ${pkgs.rofi}/bin/rofi -dpi ${toString hostFacts.display.x11Dpi} -no-config -dmenu -no-custom -format s -show-icons \
          -theme ${powerTheme})" || exit 0
      case "$choice" in
        'Lock') exec ${lib.escapeShellArg "${profile}/bin/xorg-lock"} ;;
        'Logout') action='logout'; prompt='确认：退出 dwm 会话' ;;
        'Suspend') action='suspend'; prompt='确认：挂起设备' ;;
        'Reboot') action='reboot'; prompt='确认：重新启动设备' ;;
        'Shutdown') action='poweroff'; prompt='确认：关闭设备' ;;
        *) exit 0 ;;
      esac

      confirmation="$(printf '%s\n' "$prompt" '取消' | \
        ${pkgs.rofi}/bin/rofi -dpi ${toString hostFacts.display.x11Dpi} -dmenu -no-custom -format s -p '请确认' \
          -theme ${launcherTheme} -lines 2 -columns 1)" || exit 0
      [[ "$confirmation" == "$prompt" ]] || exit 0
      case "$action" in
        logout) exec ${lib.escapeShellArg "${profile}/bin/xorg-session-exit"} ;;
        suspend) exec ${pkgs.systemd}/bin/systemctl suspend ;;
        reboot) exec ${pkgs.systemd}/bin/systemctl reboot ;;
        poweroff) exec ${pkgs.systemd}/bin/systemctl poweroff ;;
      esac
    '';
  };

  menu = pkgs.writeShellApplication {
    name = "xorg-session-menu";
    runtimeInputs = [
      pkgs.rofi
      pkgs.systemd
    ];
    text = ''
      if [[ "''${XDG_CURRENT_DESKTOP:-}" != dwm ]] || \
        ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet ${target}; then
        echo 'xorg-session-menu: an active dwm session is required' >&2
        exit 1
      fi

      choice="$(printf '%s\n' \
        '应用启动器' '音量设置' '网络设置' '蓝牙设备' '电池养护' \
        '壁纸下一张' '剪贴板历史' '通知历史' '桌面合成' '快捷键与帮助' \
        '锁屏' '电源菜单' | \
        ${pkgs.rofi}/bin/rofi -dpi ${toString hostFacts.display.x11Dpi} -dmenu -no-custom -format s -p 'Desktop' \
          -theme ${launcherTheme})" || exit 0
      case "$choice" in
        '应用启动器') exec ${launcher}/bin/xorg-launcher ;;
        '音量设置') exec ${pkgs.pavucontrol}/bin/pavucontrol ;;
        '网络设置') exec ${pkgs.networkmanagerapplet}/bin/nm-connection-editor ;;
        '蓝牙设备') exec ${pkgs.blueman}/bin/blueman-manager ;;
        '电池养护') exec ${lib.escapeShellArg "${profile}/bin/legion-conservation"} toggle ;;
        '壁纸下一张') exec ${lib.escapeShellArg "${profile}/bin/xorg-wallpaper"} next ;;
        '剪贴板历史') exec ${launcher}/bin/xorg-launcher Clipboard ;;
        '通知历史') exec ${pkgs.dunst}/bin/dunstctl history-pop ;;
        '桌面合成') exec ${effects}/bin/xorg-effects ;;
        '快捷键与帮助') exec ${help}/bin/xorg-session-help ;;
        '锁屏') exec ${lib.escapeShellArg "${profile}/bin/xorg-lock"} ;;
        '电源菜单') exec ${powerMenu}/bin/xorg-power-menu ;;
        *) exit 0 ;;
      esac
    '';
  };
in
{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    terminal = "${pkgs.kitty}/bin/kitty";
    # HM distinguishes a theme attrs set from a path string; a derivation is a set.
    theme = "${launcherTheme}";
    extraConfig = {
      modi = "drun,run,window,Clipboard:${copyqMode}/bin/xorg-rofi-copyq";
      show-icons = true;
      matching = "fuzzy";
      drun-display-format = "{name}";
      disable-history = false;
      sort = true;
      sorting-method = "fzf";
    };
  };

  xdg.configFile = {
    "rofi/launcher.rasi".source = launcherTheme;
    "rofi/power.rasi".source = powerTheme;
    "rofi/power-icons".source = powerIcons;
  };

  home.packages = [
    launcher
    notificationMenu
    status
    menu
    powerMenu
    help
    effects
  ];

  systemd.user.services.xorg-status = {
    Unit = {
      Description = "Native dwm status producer";
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
