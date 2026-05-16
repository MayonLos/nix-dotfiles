{ inputs, pkgs, ... }:
let
  wallpaperDir = ../../_assets/wallpaper;
  defaultWallpaper = ../../_assets/wallpaper/wallpaper-001.jpg;
  mangoWallpaper = pkgs.writeShellScriptBin "mango-wallpaper" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/mango-wallpaper"
    CURRENT_FILE="$STATE_DIR/current"

    mkdir -p "$STATE_DIR"

    list_wallpapers() {
      ${pkgs.findutils}/bin/find ${wallpaperDir} -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        | ${pkgs.coreutils}/bin/sort
    }

    apply_wallpaper() {
      local image="$1"

      [ -f "$image" ] || exit 1
      printf '%s\n' "$image" > "$CURRENT_FILE"
      ${pkgs.procps}/bin/pkill -x swaybg || true
      ${pkgs.swaybg}/bin/swaybg -i "$image" -m fill >/dev/null 2>&1 &
    }

    next_wallpaper() {
      mapfile -t wallpapers < <(list_wallpapers)
      [ "''${#wallpapers[@]}" -gt 0 ] || exit 1

      local current=""
      local next="''${wallpapers[0]}"
      local index

      if [ -f "$CURRENT_FILE" ]; then
        current="$(cat "$CURRENT_FILE")"
      fi

      for index in "''${!wallpapers[@]}"; do
        if [ "''${wallpapers[$index]}" = "$current" ]; then
          next="''${wallpapers[$(((index + 1) % ''${#wallpapers[@]}))]}"
          break
        fi
      done

      apply_wallpaper "$next"
    }

    random_wallpaper() {
      mapfile -t wallpapers < <(list_wallpapers)
      [ "''${#wallpapers[@]}" -gt 0 ] || exit 1

      local current=""
      local pick

      if [ -f "$CURRENT_FILE" ]; then
        current="$(cat "$CURRENT_FILE")"
      fi

      if [ "''${#wallpapers[@]}" -eq 1 ]; then
        pick="''${wallpapers[0]}"
      else
        while true; do
          pick="$(${pkgs.coreutils}/bin/printf '%s\n' "''${wallpapers[@]}" | ${pkgs.coreutils}/bin/shuf -n 1)"
          [ "$pick" != "$current" ] && break
        done
      fi

      apply_wallpaper "$pick"
    }

    init_wallpaper() {
      if [ -f "$CURRENT_FILE" ] && [ -f "$(cat "$CURRENT_FILE")" ]; then
        apply_wallpaper "$(cat "$CURRENT_FILE")"
      else
        apply_wallpaper ${defaultWallpaper}
      fi
    }

    case "''${1:-}" in
      init)
        init_wallpaper
        ;;
      next)
        next_wallpaper
        ;;
      random)
        random_wallpaper
        ;;
      daemon)
        interval="''${2:-300}"
        while true; do
          sleep "$interval"
          "$0" random
        done
        ;;
      *)
        echo "usage: mango-wallpaper {init|next|random|daemon [seconds]}" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ mangoWallpaper ];

  imports = [ inputs.mangowm.hmModules.mango ];

  wayland.windowManager.mango = {
    enable = true;
    systemd.enable = true;

    autostart_sh = ''
      # Export Wayland env to D-Bus + systemd so portals (OBS, screenshare) can connect
      dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE DISPLAY
      pkill swaybg || true
      pkill swayidle || true
      pkill wl-clip-persist || true
      ${pkgs.procps}/bin/pkill -f 'mango-wallpaper daemon' || true
      ${mangoWallpaper}/bin/mango-wallpaper init
      ${mangoWallpaper}/bin/mango-wallpaper daemon 300 &
      waybar &
      mako &
      ${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular --reconnect-tries 0 &
      # Auto-lock: 5 min idle → lock, 10 min → suspend
      ${pkgs.swayidle}/bin/swayidle -w \
        timeout 300 '${pkgs.swaylock-effects}/bin/swaylock' \
        timeout 600 'systemctl suspend' \
        before-sleep '${pkgs.swaylock-effects}/bin/swaylock' &
      # Wait for systemd env update to propagate before restarting portal-dependent services
      sleep 0.5
      systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-wlr.service
    '';

    settings = {
      # ── Monitor ────────────────────────────────────────────────────────────
      monitorrule = "name:eDP-1,width:2560,height:1600,refresh:165,scale:1.5";

      # ── Cursor ─────────────────────────────────────────────────────────────
      cursor_theme = "Bibata-Modern-Ice";
      cursor_size = 24;

      # ── Keyboard ───────────────────────────────────────────────────────────
      xkb_rules_layout = "us";
      repeat_rate = 30;
      repeat_delay = 300;

      # ── Trackpad ───────────────────────────────────────────────────────────
      tap_to_click = 1;
      tap_and_drag = 1;
      trackpad_natural_scrolling = 1;
      disable_while_typing = 1;

      # ── Mouse ──────────────────────────────────────────────────────────────
      mouse_natural_scrolling = 0;

      # ── Layout ─────────────────────────────────────────────────────────────
      default_mfact = 0.55;
      default_nmaster = 1;
      smartgaps = 1;
      no_radius_when_single = 1;
      no_border_when_single = 1;
      center_when_single_stack = 1;

      # ── Gaps ───────────────────────────────────────────────────────────────
      gappih = 6;
      gappiv = 6;
      gappoh = 10;
      gappov = 10;

      # ── Border ─────────────────────────────────────────────────────────────
      borderpx = 2;
      border_radius = 12;

      # ── Colors (One Dark) ──────────────────────────────────────────────────
      rootcolor = "0x1f2329ff";
      bordercolor = "0x3b4252ff";
      focuscolor = "0x61afefcc";
      urgentcolor = "0xe06c75ff";
      dropcolor = "0x61afef88";

      # ── Opacity ────────────────────────────────────────────────────────────
      focused_opacity = 1.0;
      unfocused_opacity = 0.95;

      # ── Blur ───────────────────────────────────────────────────────────────
      blur = 1;
      blur_layer = 1;
      blur_optimized = 1;
      blur_params_radius = 5;
      blur_params_num_passes = 2;
      blur_params_noise = 0.02;
      blur_params_brightness = 0.9;
      blur_params_contrast = 0.9;
      blur_params_saturation = 1.2;

      # ── Shadow ─────────────────────────────────────────────────────────────
      shadows = 1;
      layer_shadows = 1;
      shadow_only_floating = 0;
      shadows_size = 10;
      shadows_blur = 15;
      shadows_position_x = 0;
      shadows_position_y = 0;
      shadowscolor = "0x000000aa";

      # ── Animations ─────────────────────────────────────────────────────────
      animations = 1;
      layer_animations = 1;
      animation_type_open = "slide";
      animation_type_close = "slide";
      animation_fade_in = 1;
      animation_fade_out = 1;
      animation_duration_open = 200;
      animation_duration_close = 200;
      animation_duration_move = 200;
      animation_duration_tag = 200;
      tag_animation_direction = 1;
      animation_curve_open = "0.46,1.0,0.29,1";
      animation_curve_close = "0.08,0.92,0,1";
      animation_curve_move = "0.46,1.0,0.29,1";
      animation_curve_tag = "0.46,1.0,0.29,1";

      # ── Overview ───────────────────────────────────────────────────────────
      enable_hotarea = 0;
      overviewgappi = 8;
      overviewgappo = 30;

      # ── Regular keybindings ────────────────────────────────────────────────
      bind = [
        # Applications
        "SUPER+SHIFT,Return,spawn,foot"
        "SUPER,E,spawn,thunar"
        "SUPER,P,spawn,fuzzel"
        "SUPER+SHIFT,C,killclient,"
        "CTRL+ALT,Delete,quit,"

        # Lock screen & power menu
        "SUPER+ALT,L,spawn,swaylock"
        "SUPER+SHIFT,E,spawn,powermenu"
        "SUPER+SHIFT,W,spawn,mango-wallpaper next"
        "SUPER+CTRL,W,spawn,mango-wallpaper random"

        # Layout & sizing
        "SUPER,R,switch_layout,"
        "SUPER,F,togglefullscreen,"
        "SUPER+SHIFT,Space,togglefloating,"
        "SUPER,Minus,setmfact,-0.05"
        "SUPER,Equal,setmfact,+0.05"
        "SUPER+CTRL,N,incnmaster,+1"
        "SUPER+CTRL,M,incnmaster,-1"
        "SUPER,M,zoom,"

        # Focus — vim keys + arrows
        "SUPER,H,focusdir,left"
        "SUPER,J,focusdir,down"
        "SUPER,K,focusdir,up"
        "SUPER,L,focusdir,right"
        "SUPER,Left,focusdir,left"
        "SUPER,Down,focusdir,down"
        "SUPER,Up,focusdir,up"
        "SUPER,Right,focusdir,right"

        # Swap windows in direction
        "SUPER+SHIFT,H,exchange_client,left"
        "SUPER+SHIFT,J,exchange_client,down"
        "SUPER+SHIFT,K,exchange_client,up"
        "SUPER+SHIFT,L,exchange_client,right"
        "SUPER+SHIFT,Left,exchange_client,left"
        "SUPER+SHIFT,Down,exchange_client,down"
        "SUPER+SHIFT,Up,exchange_client,up"
        "SUPER+SHIFT,Right,exchange_client,right"

        # Tag navigation
        "SUPER+CTRL,Left,viewtoleft,0"
        "SUPER+CTRL,Right,viewtoright,0"

        # Overview / scratchpad
        "SUPER,Tab,toggleoverview,"
        "SUPER,grave,toggle_scratchpad,"
        "SUPER,I,minimized,"
        "SUPER+SHIFT,I,restore_minimized,"

        # Screenshots
        "NONE,Print,spawn,screenshot region"
        "SHIFT,Print,spawn,screenshot fullscreen"
        "CTRL+SHIFT,Print,spawn,screenshot window"
        "SUPER,Print,spawn,screenshot annotate"
        "CTRL,Print,spawn,screenshot pin"

        # Tags 1–9: switch focus
        "SUPER,1,view,1,0"
        "SUPER,2,view,2,0"
        "SUPER,3,view,3,0"
        "SUPER,4,view,4,0"
        "SUPER,5,view,5,0"
        "SUPER,6,view,6,0"
        "SUPER,7,view,7,0"
        "SUPER,8,view,8,0"
        "SUPER,9,view,9,0"

        # Tags 1–9: move window
        "SUPER+SHIFT,1,tag,1,0"
        "SUPER+SHIFT,2,tag,2,0"
        "SUPER+SHIFT,3,tag,3,0"
        "SUPER+SHIFT,4,tag,4,0"
        "SUPER+SHIFT,5,tag,5,0"
        "SUPER+SHIFT,6,tag,6,0"
        "SUPER+SHIFT,7,tag,7,0"
        "SUPER+SHIFT,8,tag,8,0"
        "SUPER+SHIFT,9,tag,9,0"
      ];

      # Media & brightness — locked-screen aware
      bindl = [
        "NONE,XF86AudioRaiseVolume,spawn,wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"
        "NONE,XF86AudioLowerVolume,spawn,wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"
        "NONE,XF86AudioMute,spawn,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        "NONE,XF86AudioMicMute,spawn,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        "NONE,XF86AudioPlay,spawn,playerctl play-pause"
        "NONE,XF86AudioStop,spawn,playerctl stop"
        "NONE,XF86AudioPrev,spawn,playerctl previous"
        "NONE,XF86AudioNext,spawn,playerctl next"
        "NONE,XF86MonBrightnessUp,spawn,brightnessctl --class=backlight set +10%"
        "NONE,XF86MonBrightnessDown,spawn,brightnessctl --class=backlight set 10%-"
      ];

      # ── Mouse bindings ─────────────────────────────────────────────────────
      mousebind = [
        "SUPER,btn_left,moveresize,curmove"
        "SUPER,btn_right,moveresize,curresize"
      ];

      # ── Touchpad gestures (3-finger swipe) ────────────────────────────────
      gesturebind = [
        "NONE,right,3,viewtoleft,0"
        "NONE,left,3,viewtoright,0"
      ];

      # ── Scroll-wheel workspace switching ──────────────────────────────────
      axisbind = [
        "SUPER,UP,viewtoleft,0"
        "SUPER,DOWN,viewtoright,0"
      ];

      # ── Per-tag layout ─────────────────────────────────────────────────────
      tagrule = [
        "id:1,layout_name:tile"
        "id:2,layout_name:tile"
        "id:3,layout_name:tile"
        "id:4,layout_name:tile"
        "id:5,layout_name:tile"
        "id:6,layout_name:tile"
        "id:7,layout_name:tile"
        "id:8,layout_name:tile"
        "id:9,layout_name:monocle"
      ];

      # ── Window rules ───────────────────────────────────────────────────────
      windowrule = [
        "isfloating:1,title:.*[Pp]icture.in.[Pp]icture.*"
        "isfloating:1,appid:org.kde.polkit-kde-authentication-agent-1"
        "isfloating:1,appid:pavucontrol"
        "isfloating:1,appid:blueman-manager"
      ];

      # ── Layer rules (blur behind bars/notifications) ───────────────────────
      layerrule = [
        "blur,layer_name:waybar"
        "blur,layer_name:mako"
        "animation_type_open:zoom,layer_name:mako"
        "animation_type_close:zoom,layer_name:mako"
      ];
    };
  };
}
