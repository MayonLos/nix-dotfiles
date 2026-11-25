{ palette, display }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  noctalia = "${pkgs.local.noctaliaDesktop.noctalia}/bin/noctalia";
  # Noctalia owns the shell surface (launcher, panels, OSD, screenshots, lock),
  # so compositor binds only forward verbs to it; hardware keys go through it
  # as well to keep one OSD and one volume/brightness implementation.
  nc = command: "${noctalia} msg ${command}";

  # Repository commands are installed by Home Manager into the per-user profile
  # (home-manager.useUserPackages = true). The login wrapper starts with the
  # greeter environment, so it cannot rely on the profile being on PATH.
  profile = config.home.profileDirectory;

  # One Dark. Hyprland parses rgba(RRGGBBAA) with 8-bit hex components.
  rgba = hex: "rgba(${lib.removePrefix "#" hex}ff)";

  kitty = lib.getExe pkgs.kitty;
  markShot = "${pkgs.local.mark-shot}/bin/mark-shot";

  # host.facts.display carries an exact refresh rate; Hyprland matches the
  # closest available mode, so round to the integer printed by typical mode
  # listings. "preferred" is the documented fallback when facts change shape.
  refreshSuffix =
    if display ? refresh then "@${toString (builtins.floor (display.refresh + 0.5))}" else "";
  mode =
    if display ? refresh then
      "${toString display.width}x${toString display.height}${refreshSuffix}"
    else
      "preferred";
  # Hyprland requires the logical size to be integral: 1.5 maps 2560x1600 to
  # 1706.67 px and triggers its "invalid scale" notification. 1.6 gives an
  # exact 1600x1000 logical output (same size Noctalia reports for this panel).
  scale = 1.6;
  monitor = "${display.name}, ${mode}, 0x0, ${builtins.toJSON scale}";

  # Numbered workspaces mirror the Mango tag digits and the Umbriel binds.
  workspaces = builtins.concatMap (
    number:
    let
      digit = toString number;
    in
    [
      "SUPER, ${digit}, workspace, ${digit}"
      "SUPER SHIFT, ${digit}, movetoworkspace, ${digit}"
    ]
  ) (lib.range 1 9);
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    # stateVersion 25.11 predates the HM 26.05 lua default, but pin hyprlang
    # explicitly: the whole file below (monitor rules, bind syntax) is hyprlang.
    configType = "hyprlang";
    # HM's systemd integration imports the Wayland/session variables into the
    # user manager and defines hyprland-session.target.
    systemd.enable = true;
    # The NixOS module owns the portal: it installs xdg-desktop-portal-hyprland
    # system-wide and writes /etc/xdg/xdg-desktop-portal/hyprland-portals.conf.
    # Leaving HM's portalPackage at its default would additionally export a
    # user-wide NIX_XDG_DESKTOP_PORTAL_DIR from this profile and hide the
    # wlr/gtk backends the Mango and Umbriel sessions rely on.
    portalPackage = null;

    settings = {
      monitor = [ monitor ];

      # The compositor starts the shell and the repository's polkit agent, the
      # same pairing as the Umbriel session. Paths are absolute because the
      # greeter environment has no Home Manager profile on PATH.
      # The shell, polkit agent and clipboard bridge are systemd user services
      # started from hyprland-session.target; the compositor only supplies the
      # Wayland session and its window rules.

      general = {
        gaps_in = 8;
        gaps_out = 8;
        border_size = 1;
        "col.active_border" = rgba palette.blue;
        "col.inactive_border" = rgba palette.border;
        resize_on_border = false;
        layout = "dwindle";
      };

      # Minimal One Dark surface: square corners, no shadows, light blur.
      decoration = {
        rounding = 0;
        shadow.enabled = false;
        blur = {
          enabled = true;
          size = 3;
          passes = 1;
        };
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          tap-to-click = true;
          natural_scroll = true;
        };
      };

      animations = {
        enabled = !palette.reducedMotion;
        bezier = [ "easeOut, 0.05, 0.9, 0.1, 1.0" ];
        animation = [
          "global, 1, 8, easeOut"
          "windows, 1, 6, easeOut"
          "fade, 1, 6, easeOut"
          "workspaces, 1, 5, easeOut"
        ];
      };

      bind = [
        # Applications and shell.
        "SUPER, Return, exec, ${kitty}"
        "SUPER, E, exec, ${profile}/bin/workspace-files"
        "SUPER, B, exec, ${profile}/bin/workspace-browser"
        "ALT, Space, exec, ${nc "panel-toggle launcher"}"
        "SUPER, V, exec, ${nc "panel-toggle clipboard"}"
        "SUPER, Escape, exec, ${nc "panel-toggle session"}"
        "SUPER ALT, L, exec, ${nc "session lock"}"

        # Focus and window movement, same HJKL and arrow split as Mango.
        "SUPER, H, movefocus, l"
        "SUPER, J, movefocus, d"
        "SUPER, K, movefocus, u"
        "SUPER, L, movefocus, r"
        "SUPER, Left, movefocus, l"
        "SUPER, Down, movefocus, d"
        "SUPER, Up, movefocus, u"
        "SUPER, Right, movefocus, r"
        "SUPER SHIFT, H, movewindow, l"
        "SUPER SHIFT, J, movewindow, d"
        "SUPER SHIFT, K, movewindow, u"
        "SUPER SHIFT, L, movewindow, r"
        "SUPER SHIFT, Left, movewindow, l"
        "SUPER SHIFT, Down, movewindow, d"
        "SUPER SHIFT, Up, movewindow, u"
        "SUPER SHIFT, Right, movewindow, r"
        "SUPER, Tab, focuscurrentorlast"
        "ALT, Tab, cyclenext"
        "ALT SHIFT, Tab, cyclenext, prev"

        # Window state.
        "SUPER, Q, killactive"
        "SUPER, Space, togglefloating"
        "SUPER, F, fullscreen"

        # Screenshots: Noctalia owns region capture, mark-shot keeps the
        # annotated/scrolling capture and the OCR wrappers stay repository
        # scripts. OCR wrappers are installed by the Mango session's
        # screenshot.nix and are user-wide because Home Manager is shared.
        ", Print, exec, ${markShot}"
        "SUPER, Print, exec, ${nc "screenshot-region"}"
        "SHIFT, Print, exec, ${markShot} --scroll"
        "SUPER SHIFT, Print, exec, ${profile}/bin/ocr-screen"
        "CTRL SHIFT, Print, exec, ${profile}/bin/ocr-region"
      ]
      ++ workspaces;

      # Locked binds: the Noctalia OSD stays reachable while the session is
      # locked, matching the Umbriel allow_when_locked hardware keys.
      bindl = [
        ", XF86AudioRaiseVolume, exec, ${nc "volume-up"}"
        ", XF86AudioLowerVolume, exec, ${nc "volume-down"}"
        ", XF86AudioMute, exec, ${nc "volume-mute"}"
        ", XF86AudioMicMute, exec, ${nc "mic-mute"}"
        ", XF86MonBrightnessUp, exec, ${nc "brightness-up"}"
        ", XF86MonBrightnessDown, exec, ${nc "brightness-down"}"
        ", XF86AudioPlay, exec, ${nc "media toggle"}"
        ", XF86AudioNext, exec, ${nc "media next"}"
        ", XF86AudioPrev, exec, ${nc "media previous"}"
      ];

    };
  };
}
