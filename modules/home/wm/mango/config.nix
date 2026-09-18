{
  inputs,
  config,
  lib,
  ...
}:

{
  imports = [ inputs.mango.hmModules.mango ];

  wayland.windowManager.mango = {
    enable = true;

    # Mango's systemd hook already imports the session variables and starts
    # mango-session.target, so duplicating that environment update here
    # would only race the same environment update.
    systemd.enable = true;

    settings = {
      # The broad default is dwm's master-stack tile layout for all tags.
      tagrule = [
        "id:*,layout_name:tile"
      ];

      monitorrule = [
        "name:^eDP-1$,width:2560,height:1600,refresh:165.002,x:0,y:0,scale:1.5,vrr:1"
      ];

      # Let X11 clients render at real pixels instead of being upscaled.
      #
      # Measured on 2026-09-18 with the default (0): `xdpyinfo` reported the X
      # screen as **1707x1067**, i.e. 2560/1.5 -- Xwayland runs at the LOGICAL
      # size and mango stretches every X surface 1.5x to fill the panel. That
      # is a bitmap upscale, so every X11 client is soft no matter what it
      # does internally; Steam's UI was the complaint that surfaced it, and the
      # NIXOS_OZONE_WL comment below is the same problem seen from the other
      # side.
      #
      # With 1, src/manage/client.c:xwayland_client_scale returns the monitor
      # scale, so mango sizes each X window in *physical* pixels and presents
      # it 1:1 ("windows display exactly 1:1", its own comment) -- nothing is
      # resampled. Measured with an xclock after flipping it:
      #
      #   compositor logical geometry   936 x 1010
      #   X-side geometry              1392 x 1503     ratio 1.487
      #
      # i.e. the client now renders into a buffer 1.5x its logical size. The
      # root X screen still *reports* 1707x1067; only per-window geometry
      # changes, which is enough.
      #
      # X clients then look small unless they scale themselves -- which is
      # exactly what `Xft.dpi: 144` in base/xresources.nix is for, and it is
      # already merged into this server (`xrdb -query` returns it). The two
      # settings are a pair; neither works alone.
      xwayland_ignore_scale = 1;

      # mango is exec'd straight from the session desktop file, not through a
      # login shell, so it inherits none of Home Manager's session variables --
      # niri got them because niri-session is a shell wrapper that sources
      # hm-session-vars.sh. Everything mango spawns (noctalia, and every app
      # noctalia's launcher starts) inherits mango's environment, so the whole
      # set has to be put back here. `env=` is setenv'd into the compositor's
      # own process at config-parse time (src/config/parse_config.c:335).
      #
      # The one that bites hardest is NIXOS_OZONE_WL: the nixpkgs Electron
      # wrappers add `--ozone-platform=wayland` only when it is set, so without
      # it every Electron app lands on XWayland and renders visibly blurry at
      # this 1.5x scale. Mirrored from home.sessionVariables rather than
      # retyped, so base/session-vars.nix stays the single source of truth.
      #
      # Values needing shell expansion are dropped: mango expands `~/` and
      # nothing else, so a `${...}` or `$(...)` would be set as that literal
      # string. TMUX_TMPDIR is the one that hits this today; shells still get
      # it from hm-session-vars.sh, which is where it matters.
      env =
        lib.mapAttrsToList (n: v: "${n},${toString v}") (
          lib.filterAttrs (_: v: !(lib.hasInfix "$" (toString v))) config.home.sessionVariables
        )
        ++ [
          # Not a session variable: niri carried this in its own `environment`
          # block. Without it Qt apps come up in default light Fusion and
          # base/qt.nix's qt6ct palette is never consulted.
          "QT_QPA_PLATFORMTHEME,qt6ct"
        ];

      # Carried over from niri's `cursor` block. cursor_hide_on_keypress is
      # mango's spelling of niri's `hide-when-typing`; there is no global
      # prefer-no-csd equivalent (mango's allow_csd is a windowrule field only,
      # and it does not ask clients for decorations anyway).
      cursor_theme = "Bibata-Modern-Ice";
      cursor_size = 24;
      cursor_hide_on_keypress = 1;

      # Noctalia draws its own layer effects, so only Mango's window blur and
      # shadows remain enabled.
      blur = 1;
      blur_layer = 0;
      blur_optimized = 1;
      blur_params_num_passes = 2;
      blur_params_radius = 5;
      blur_params_noise = 0.02;
      blur_params_brightness = 0.9;
      blur_params_contrast = 0.9;
      blur_params_saturation = 1.0;
      layer_animations = 0;
      shadows = 1;
      layer_shadows = 0;
      shadow_only_floating = 0;
      shadows_size = 4;
      shadows_blur = 12;
      shadows_position_x = 2;
      shadows_position_y = 2;
      shadowscolor = "0x000000ff";

      borderpx = 4;
      border_radius = 18;
      gappih = 5;
      gappiv = 5;
      gappoh = 10;
      gappov = 10;
      smartgaps = 0;
      no_border_when_single = 0;

      animations = 1;
      animation_type_open = "zoom";
      animation_type_close = "slide";
      animation_fade_in = 1;
      animation_fade_out = 1;
      fadein_begin_opacity = 0.5;
      fadeout_begin_opacity = 0.5;
      zoom_initial_ratio = 0.4;
      zoom_end_ratio = 0.8;
      animation_duration_move = 500;
      animation_duration_open = 400;
      animation_duration_tag = 300;
      animation_duration_close = 300;
      animation_duration_focus = 0;
      animation_curve_open = "0.46,1.0,0.29,0.99";
      animation_curve_move = "0.46,1.0,0.29,0.99";
      animation_curve_tag = "0.46,1.0,0.29,0.99";
      animation_curve_close = "0.46,1.0,0.29,0.99";
      animation_curve_focus = "0.46,1.0,0.29,0.99";
      animation_curve_opafadein = "0.46,1.0,0.29,0.99";
      animation_curve_opafadeout = "0.5,0.5,0.5,0.5";
      tag_animation_direction = 1;

      scroller_structs = 20;
      scroller_default_proportion = 0.9;
      scroller_focus_center = 0;
      scroller_prefer_center = 0;
      scroller_prefer_overspread = 1;
      edge_scroller_pointer_focus = 1;
      edge_scroller_focus_allow_speed = 0.0;
      scroller_proportion_preset = "0.5,0.8,1.0";
      scroller_ignore_proportion_single = 1;
      scroller_default_proportion_single = 1.0;

      # Avoid accidental tag changes at the screen edge while a game or video
      # is fullscreen, and keep the display awake during fullscreen playback.
      hotarea_disable_on_fullscreen = 1;
      idleinhibit_when_fullscreen = 1;

      new_is_master = 1;
      default_mfact = 0.55;
      default_nmaster = 1;
      tag_num = 9;

      repeat_rate = 30;
      repeat_delay = 400;
      numlockon = 1;
      xkb_rules_layout = "us";
      tap_to_click = 1;
      trackpad_natural_scrolling = 1;
      trackpad_disable_while_typing = 1;
      trackpad_scroll_method = 1;
      trackpad_click_method = 1;
      trackpad_middle_button_emulation = 1;
      trackpad_accel_profile = 2;
      button_map = 0;
      sloppyfocus = 1;

      # Window rules use app-id/title regular-expression matching. Mango has no
      # layer-rule equivalent, so Noctalia's layer effects
      # are handled by the effect settings above instead.
      windowrule = [
        "isfloating:1,width:0.5,isnoborder:1,appid:^swayimg$"
        "isfloating:1,appid:^thunar$,title:^(Rename|重命名)"
        "isfloating:1,width:480,appid:^zen-beta$,title:^Picture-in-Picture$"
        "isfloating:1,appid:^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor|org\\.gnome\\.Calculator|xdg-desktop-portal-gtk)$"
        "isfloating:1,appid:^(polkit-.*|org\\.freedesktop\\.PolicyKit.*)$"
        "isfloating:1,width:1080,height:920,appid:^dev\\.noctalia\\.Noctalia\\.Settings$"
        "vrr_only_fullscreen:1,isnoradius:1,appid:^steam_app_"
        "focused_opacity:0.8,unfocused_opacity:0.8,appid:^foot$"
      ];

      # Launches, Noctalia shell controls, tag navigation, and dwm-style
      # master-stack operations.
      bind = [
        "SUPER,E,spawn,thunar"
        "SUPER,B,spawn,zen-beta"
        "SUPER,Return,spawn,foot"
        "ALT,space,spawn,noctalia msg panel-toggle launcher"
        "SUPER,S,spawn,noctalia msg panel-toggle control-center"
        "SUPER+ALT,L,spawn,noctalia msg session lock"
        "SUPER,0,toggleoverview"
        "SUPER,Q,killclient"

        "SUPER,H,focusdir,left"
        "SUPER,Left,focusdir,left"
        "SUPER,J,focusdir,down"
        "SUPER,Down,focusdir,down"
        "SUPER,K,focusdir,up"
        "SUPER,Up,focusdir,up"
        "SUPER,L,focusdir,right"
        "SUPER,Right,focusdir,right"

        "SUPER+CTRL,H,exchange_client,left"
        "SUPER+CTRL,Left,exchange_client,left"
        "SUPER+CTRL,J,exchange_client,down"
        "SUPER+CTRL,Down,exchange_client,down"
        "SUPER+CTRL,K,exchange_client,up"
        "SUPER+CTRL,Up,exchange_client,up"
        "SUPER+CTRL,L,exchange_client,right"
        "SUPER+CTRL,Right,exchange_client,right"

        "SUPER+SHIFT+CTRL,H,move_client,left"
        "SUPER+SHIFT+CTRL,J,move_client,down"
        "SUPER+SHIFT+CTRL,K,move_client,up"
        "SUPER+SHIFT+CTRL,L,move_client,right"

        "SUPER,Page_Down,viewtoright"
        "SUPER,U,viewtoright"
        "SUPER,Page_Up,viewtoleft"
        "SUPER,I,viewtoleft"
        "SUPER+ALT,J,overcircle,current_prev"
        "SUPER+ALT,K,overcircle,current_next"
        "SUPER+CTRL,Page_Down,tagtoright"
        "SUPER+CTRL,U,tagtoright"
        "SUPER+CTRL,Page_Up,tagtoleft"
        "SUPER+CTRL,I,tagtoleft"
        # niri had two distinct pairs here -- move-column-to-workspace and
        # move-workspace -- and mango has only the first, so the Shift pair was
        # a byte-identical duplicate of the Ctrl pair above. Reused for the one
        # dwm knob the layout has and nothing else could reach: nmaster.
        "SUPER+SHIFT,I,incnmaster,1"
        "SUPER+SHIFT,U,incnmaster,-1"

        "SUPER,1,view,1"
        "SUPER,2,view,2"
        "SUPER,3,view,3"
        "SUPER,4,view,4"
        "SUPER,5,view,5"
        "SUPER,6,view,6"
        "SUPER,7,view,7"
        "SUPER,8,view,8"
        "SUPER,9,view,9"
        # tag follows, tagsilent does not: tag_client() calls
        # client_switch_view() and then focuses the moved window
        # (src/manage/client.c), while tag_silent() only rewrites c->tags.
        # Shift gets the one that follows because that is the reflex; Ctrl
        # keeps the stay-put variant for parking a window out of the way.
        "SUPER+CTRL,1,tagsilent,1"
        "SUPER+CTRL,2,tagsilent,2"
        "SUPER+CTRL,3,tagsilent,3"
        "SUPER+CTRL,4,tagsilent,4"
        "SUPER+CTRL,5,tagsilent,5"
        "SUPER+CTRL,6,tagsilent,6"
        "SUPER+CTRL,7,tagsilent,7"
        "SUPER+CTRL,8,tagsilent,8"
        "SUPER+CTRL,9,tagsilent,9"
        "SUPER+SHIFT,1,tag,1"
        "SUPER+SHIFT,2,tag,2"
        "SUPER+SHIFT,3,tag,3"
        "SUPER+SHIFT,4,tag,4"
        "SUPER+SHIFT,5,tag,5"
        "SUPER+SHIFT,6,tag,6"
        "SUPER+SHIFT,7,tag,7"
        "SUPER+SHIFT,8,tag,8"
        "SUPER+SHIFT,9,tag,9"

        # setmfact keeps dwm's convention (src/dispatch/bind.c, set_master_factor):
        # an argument below 1.0 is a *delta* applied to the current mfact, and
        # only >= 1.0 is absolute, taken as value - 1.0. So the two absolute
        # binds below read 1.55 and 1.9, not 0.55 and 0.9 -- written the obvious
        # way they are deltas that overshoot the 0.9 guard and silently do
        # nothing at all.
        "SUPER,Home,focusstack,prev"
        "SUPER,End,focusstack,next"
        "SUPER,Tab,focuslast"
        # niri's Mod+R was switch-preset-column-width; this is its real
        # counterpart, cycling scroller_proportion_preset on a scroller tag.
        # It used to be a second copy of SUPER+Equal.
        "SUPER,R,switch_proportion_preset"
        "SUPER+CTRL,R,setmfact,1.55"
        "SUPER,F,togglemaximizescreen"
        "SUPER+SHIFT,F,togglefullscreen"
        "SUPER+CTRL,F,setmfact,1.9"
        "SUPER,C,centerwin"
        "SUPER,Minus,setmfact,-0.05"
        "SUPER,Equal,setmfact,+0.05"
        "SUPER+SHIFT,Minus,resizewin,0,-10"
        "SUPER+SHIFT,Equal,resizewin,0,+10"
        "SUPER+SHIFT,space,togglefloating"
        "SUPER,W,switch_layout"
        "SUPER,Z,zoom"
        "SUPER+SHIFT,G,togglegaps"
        # mango hot-reloads config.conf; without a bind there is no way to ask
        # for it after editing the file by hand.
        "SUPER+ALT,R,reload_config"

        "NONE,Print,spawn,mark-shot"
        "SHIFT,Print,spawn,wayscrollshot"
        "SUPER+SHIFT,E,spawn,noctalia msg panel-toggle session"
        "CTRL+ALT,Delete,quit"
        "SUPER,V,spawn,noctalia msg panel-toggle clipboard"
        "SUPER+SHIFT,P,sleep_monitor,eDP-1"
        "SUPER+SHIFT,W,spawn,noctalia msg wallpaper-random"
        "SUPER+SHIFT,A,spawn,noctalia msg caffeine-toggle"

        "SUPER+SHIFT,R,setkeymode,resize"
        "SUPER,grave,toggle_scratchpad"
        "SUPER+ALT,T,switcher,next"
      ];

      # Match the old niri mouse workflow: Super+left-drag moves the focused
      # window and Super+right-drag resizes it.
      mousebind = [
        "SUPER,btn_left,moveresize,curmove"
        "SUPER,btn_right,moveresize,curresize"
      ];

      bindl = [
        "NONE,XF86AudioRaiseVolume,spawn,noctalia msg volume-up"
        "NONE,XF86AudioLowerVolume,spawn,noctalia msg volume-down"
        "NONE,XF86AudioMute,spawn,noctalia msg volume-mute"
        "NONE,XF86AudioMicMute,spawn,noctalia msg mic-mute"
        "NONE,XF86MonBrightnessUp,spawn,noctalia msg brightness-up"
        "NONE,XF86MonBrightnessDown,spawn,noctalia msg brightness-down"
        "NONE,XF86AudioPlay,spawn,playerctl play-pause"
        "NONE,XF86AudioStop,spawn,playerctl stop"
        "NONE,XF86AudioPrev,spawn,playerctl previous"
        "NONE,XF86AudioNext,spawn,playerctl next"
      ];

      keymode.resize.bind = [
        "NONE,H,resizewin,-10,0"
        "NONE,Left,resizewin,-10,0"
        "NONE,J,resizewin,0,+10"
        "NONE,Down,resizewin,0,+10"
        "NONE,K,resizewin,0,-10"
        "NONE,Up,resizewin,0,-10"
        "NONE,L,resizewin,+10,0"
        "NONE,Right,resizewin,+10,0"
        "NONE,Escape,setkeymode,default"
      ];
    };

    # Mango has no column consume/expel, first/last-column movement,
    # preset column/window heights, center-visible-columns, floating/tiling
    # focus switching, keyboard-shortcut inhibition, or compositor screenshot
    # dispatcher. Those actions are intentionally not recreated with unrelated
    # commands.

    # `systemd.enable` above only *defines* mango-session.target. The line that
    # actually runs `dbus-update-activation-environment --systemd` and
    # `systemctl --user start mango-session.target` lives in the autostart
    # script the module generates -- and the module only writes that script,
    # and only adds its `exec-once`, when `autostart_sh` is non-empty
    # (nix/hm-modules.nix). Starting noctalia from `extraConfig` instead left
    # autostart_sh empty, so the target never started; graphical-session.target
    # BindsTo it, so every user unit hanging off it stayed dead -- cliphist,
    # xrdb-merge, fcitx5-daemon -- and D-Bus-activated launches never saw
    # NIXOS_OZONE_WL, which sent Electron apps to XWayland and made them blurry.
    # Anything to autostart belongs here, not in an `exec-once` of its own.
    autostart_sh = ''
      noctalia &
    '';

    extraConfig = ''
      # Noctalia's builtin "mango" theme template renders the palette to
      # $XDG_CONFIG_HOME/mango/noctalia.conf (assets/templates/builtin.toml).
      # Sourced last so those colours win over anything set above.
      #
      # source-optional, not source: the file does not exist until Noctalia
      # first applies a theme, and a plain `source` of a missing file is a
      # parse error. This is what niri needed a seed-an-empty-file activation
      # script for -- mango has the optional form built in.
      source-optional=${config.xdg.configHome}/mango/noctalia.conf
    '';
  };
}
