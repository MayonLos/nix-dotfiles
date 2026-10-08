{
  inputs,
  config,
  lib,
  ...
}:

let
  desktop = import ../../../../lib/desktop.nix;
in

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
        "name:^${desktop.primaryOutput}$,width:2560,height:1600,refresh:165.002,x:0,y:0,scale:1.5,vrr:1"
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
      env = lib.mapAttrsToList (n: v: "${n},${toString v}") (
        lib.filterAttrs (_: v: !(lib.hasInfix "$" (toString v))) config.home.sessionVariables
      );

      # Carried over from niri's `cursor` block. cursor_hide_on_keypress is
      # mango's spelling of niri's `hide-when-typing`; there is no global
      # prefer-no-csd equivalent (mango's allow_csd is a windowrule field only,
      # and it does not ask clients for decorations anyway).
      cursor_theme = desktop.cursor.name;
      cursor_size = desktop.cursor.size;
      cursor_hide_on_keypress = 1;

      # Noctalia draws its own layer effects, so only Mango's window blur and
      # shadows remain enabled.
      blur = 1;
      blur_layer = 0;
      blur_optimized = 1;
      blur_params_num_passes = 2;
      blur_params_radius = 6;
      blur_params_noise = 0.02;
      blur_params_brightness = 0.9;
      blur_params_contrast = 0.9;
      blur_params_saturation = 1.0;
      layer_animations = 0;
      shadows = 1;
      layer_shadows = 0;
      shadow_only_floating = 0;
      shadows_size = 6;
      shadows_blur = 16;
      shadows_position_x = 2;
      shadows_position_y = 4;
      shadowscolor = "0x00000099";

      # Keep client opacity independent from focus dimming: Mango composites
      # the dim overlay separately, so unfocused windows can stay crisp while
      # still reading as secondary.
      dim_enable = 1;
      dim_focused_color = "0x00000000";
      dim_unfocused_color = "0x00000022";

      borderpx = 2;
      # Match the compact Noctalia bar's corner radius.
      border_radius = 12;
      gappih = 5;
      gappiv = 5;
      gappoh = 10;
      gappov = 10;
      smartgaps = 0;
      no_border_when_single = 0;

      animations = 1;
      animation_type_open = "zoom";
      animation_type_close = "zoom";
      animation_fade_in = 1;
      animation_fade_out = 1;
      fadein_begin_opacity = 0.5;
      fadeout_begin_opacity = 0.5;
      zoom_initial_ratio = 0.88;
      zoom_end_ratio = 0.9;
      animation_duration_move = 180;
      animation_duration_open = 240;
      animation_duration_tag = 200;
      animation_duration_close = 180;
      animation_duration_focus = 0;
      animation_curve_open = "0.46,1.0,0.29,0.99";
      animation_curve_move = "0.46,1.0,0.29,0.99";
      animation_curve_tag = "0.46,1.0,0.29,0.99";
      animation_curve_close = "0.46,1.0,0.29,0.99";
      animation_curve_focus = "0.46,1.0,0.29,0.99";
      animation_curve_opafadein = "0.46,1.0,0.29,0.99";
      # Was "0.5,0.5,0.5,0.5" -- a bezier straight down the diagonal, i.e.
      # constant velocity. Every other curve here, including its own
      # opafadein counterpart, eases; the fade-out was the one motion in the
      # compositor that did not.
      animation_curve_opafadeout = "0.46,1.0,0.29,0.99";
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
      # switch_layout walks only this list. The three names are layouts[]
      # entries in the pinned arrange.c: tile, scroller, monocle.
      circle_layout = "tile,scroller,monocle";

      # Tabbed monocle: the full-screen stack gets a tab bar (click to switch)
      # instead of keyboard-only cycling. deck_tab_mode stays at its default:
      # deck is not in circle_layout, and its master+stack shape is a
      # different workflow. Tab bar colors/height come from mango's defaults,
      # which already match Tokyo Night.
      # Tab bar keeps mango's default styling on purpose: the upstream colors
      # (bg 1a1b26, blue focus chip) read better under the Noctalia bar than
      # the muted window-chrome variant tried on 2026-10-02.
      monocle_tab_mode = 1;

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

      # 4 selects the nearest corner from the press point. 0 leaves the
      # pointer where it is. Pinned defaults are the southeast corner and a
      # warp (pointer.c treats 0 as "do not warp", not as "no corner").
      drag_corner = 4;
      drag_warp_cursor = 0;
      enable_floating_snap = 1;
      snap_distance = 12;

      # Window rules use app-id/title regular-expression matching. Mango has no
      # layer-rule equivalent, so Noctalia's layer effects
      # are handled by the effect settings above instead.
      windowrule = [
        "isfloating:1,width:0.5,isnoborder:1,appid:^swayimg$"
        "isfloating:1,appid:^thunar$,title:^(Rename|重命名)"
        "isfloating:1,width:480,appid:^[Ff]irefox$,title:^Picture-in-Picture$"
        # blueman-manager, nm-connection-editor and org.gnome.Calculator were
        # in this alternation and are installed nowhere -- not on PATH, not in
        # any module. Template leftovers. Add an appid back when the program
        # that carries it actually arrives, not before: a rule that cannot
        # match is indistinguishable from one that is broken.
        "isfloating:1,appid:^(pavucontrol|org\\.pulseaudio\\.pavucontrol|xdg-desktop-portal-gtk)$"
        # No polkit rule. This host runs no standalone polkit GUI agent --
        # noctalia's built-in one is the only authentication agent (see
        # noctalia.nix's `polkit_agent`), and it draws in the shell rather than
        # opening a top-level window, so nothing can ever carry a `polkit-*` or
        # `org.freedesktop.PolicyKit*` appid here.
        # `.Settings` was never an appid. Measured with `mmsg get all-clients`
        # while the window was open: it reports `dev.noctalia.Noctalia`, and the
        # window came up tiled at 936x1010 instead of the floating 1080x920 this
        # line asks for -- the rule had simply never matched anything.
        "isfloating:1,width:1080,height:920,appid:^dev\\.noctalia\\.Noctalia$"
        "vrr_only_fullscreen:1,isnoradius:1,appid:^steam_app_"
        # Kitty applies its own 0.92 alpha to terminal backgrounds. Keep the
        # whole client opaque so glyphs and foregrounds stay crisp; focus dim
        # remains Mango's separate overlay above. The named scratchpad uses
        # its own app id, so it has to be listed here too.
        "focused_opacity:1.0,unfocused_opacity:1.0,appid:^(kitty|mayon-scratch)$"
        "isnamedscratchpad:1,appid:^mayon-scratch$"
      ];

      # Launches, Noctalia shell controls, tag navigation, and dwm-style
      # master-stack operations.
      bind = [
        "SUPER,E,spawn,thunar"
        "SUPER,B,spawn,firefox"
        "SUPER,Return,spawn,kitty"
        # Title argument "none" means match by app id only. Size stays at the
        # scratchpad default ratios; do not set width or height here.
        "SUPER+SHIFT,Return,toggle_named_scratchpad,mayon-scratch,none,kitty --class=mayon-scratch"
        "ALT,space,spawn,noctalia msg panel-toggle launcher"
        "SUPER,S,spawn,noctalia msg panel-toggle control-center"
        # No argument: the keybind path has no client, so this toggles tag 0
        # on the selected monitor.
        "SUPER+SHIFT,S,toggle_special_tag"
        "SUPER+ALT,L,spawn,noctalia msg session lock"
        "SUPER,0,toggleoverview"
        "SUPER+SHIFT,0,togglejump"

        "SUPER,H,focusdir,left"
        "SUPER,Left,focusdir,left"
        "SUPER,J,focusdir,down"
        "SUPER,Down,focusdir,down"
        "SUPER,K,focusdir,up"
        "SUPER,Up,focusdir,up"
        "SUPER,L,focusdir,right"
        "SUPER,Right,focusdir,right"

        "SUPER+SHIFT,H,move_client,left"
        "SUPER+SHIFT,Left,move_client,left"
        "SUPER+SHIFT,J,move_client,down"
        "SUPER+SHIFT,Down,move_client,down"
        "SUPER+SHIFT,K,move_client,up"
        "SUPER+SHIFT,Up,move_client,up"
        "SUPER+SHIFT,L,move_client,right"
        "SUPER+SHIFT,Right,move_client,right"

        # Directions only. parse_monitor_arg accepts left/right/up/down.
        # HJKL is not bound: those chords used to be exchange_client.
        "SUPER+CTRL,Left,tagmon,left"
        "SUPER+CTRL,Down,tagmon,down"
        "SUPER+CTRL,Up,tagmon,up"
        "SUPER+CTRL,Right,tagmon,right"

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
        # Super+R enters resize. The scroller width cycle moved to
        # Super+Shift+R and still returns immediately outside scroller.
        "SUPER,R,setkeymode,resize"
        "SUPER+CTRL,R,setmfact,1.55"
        "SUPER,F,togglemaximizescreen"
        "SUPER+SHIFT,F,togglefullscreen"
        "SUPER+CTRL,F,setmfact,1.9"
        "SUPER,C,centerwin"
        "SUPER,Minus,setmfact,-0.05"
        "SUPER,Equal,setmfact,+0.05"
        # Unsigned 0 is a target size on a floating window. +0 is a zero delta
        # on both tiled and floating windows, so the other axis stays put.
        "SUPER+SHIFT,Minus,resizewin,+0,-10"
        "SUPER+SHIFT,Equal,resizewin,+0,+10"
        "SUPER+SHIFT,space,togglefloating"
        "SUPER,W,switch_layout"
        "SUPER,Z,zoom"
        "SUPER+SHIFT,G,togglegaps"

        "NONE,Print,spawn,mark-shot"
        "SHIFT,Print,spawn,wayscrollshot"
        # Screen-text OCR, so the whole Print family is capture: bare = region
        # screenshot, Shift = scrolling capture, Super = OCR the selection,
        # Super+Shift = OCR the entire desktop. Scripts come from
        # programs/apps/screenshot.nix.
        #
        # This exists instead of using noctalia's fel/ocr tile because that tile
        # is not automatic: the control center renders `control_center.shortcuts`,
        # a configured list whose only default is wifi/bluetooth/caffeine/
        # nightlight/notification/power_profile (config_types.cpp:53), and the
        # picker that adds entries is capped at six (settings_registry.cpp:1442).
        # The plugin's catalog entry only makes it selectable. A bind needs no
        # slot and no noctalia restart.
        "SUPER,Print,spawn,ocr-region"
        "SUPER+SHIFT,Print,spawn,ocr-screen"
        "CTRL+ALT,Delete,spawn,noctalia msg panel-toggle session"
        "SUPER,V,spawn,noctalia msg panel-toggle clipboard"
        "SUPER+SHIFT,P,sleep_monitor,${desktop.primaryOutput}"
        "SUPER+SHIFT,O,wakeup_monitor,${desktop.primaryOutput}"
        "SUPER+SHIFT,W,spawn,noctalia msg wallpaper-random"
        "SUPER+SHIFT,A,spawn,noctalia msg caffeine-toggle"

        "SUPER+SHIFT,R,switch_proportion_preset"
        # These two are a pair. `toggle_scratchpad` only ever acts on a client
        # whose `is_in_scratchpad` flag is set, and mango sets that flag only
        # inside `set_minimized()` (src/manage/client.c) -- so without a
        # minimize bind the toggle is a permanent no-op. It was: dispatching it
        # by hand returned `{"success":true}` and changed nothing.
        "SUPER+SHIFT,grave,minimized"
        "SUPER,grave,toggle_scratchpad"
        "SUPER+ALT,T,switcher,next"
      ];

      # Default-mode gestures. none is a real modifier token and sets no
      # bits. Four-finger left/right switch occupied tags; both vertical
      # swipes toggle overview. Three-finger swipes are focusdir.
      gesturebind = [
        "none,left,4,viewnext_have_client"
        "none,right,4,viewprev_have_client"
        "none,up,4,toggleoverview"
        "none,down,4,toggleoverview"
        "none,up,3,focusdir,up"
        "none,down,3,focusdir,down"
        "none,left,3,focusdir,left"
        "none,right,3,focusdir,right"
      ];

      # Binds that stay live in EVERY keymode. Three facts forced this block
      # into existence, all read off the pinned source:
      #
      #   1. A bind fires only when its mode matches. keyboard.c:587-589 accepts
      #      `iscommonmode || (isdefaultmode && currently-default) ||
      #      mode-name-equal`, so the moment a non-default mode is entered,
      #      every bind above goes dead. pointer.c:389/1475 and
      #      trackpad.c:65/215 apply the same test to mouse and gesture binds.
      #   2. `reload_config` does NOT reset the mode. `server.key_mode` is
      #      written only by set_key_mode() (dispatch/bind.c:900) and read by
      #      the input handlers and IPC -- the reload path never touches it.
      #      Reloading from inside a mode keeps you in that mode, so a config
      #      edit that drops or renames the mode would leave `common` as the
      #      only reachable layer.
      #   3. A bare key must not go here. `common` applies globally, so a
      #      `NONE,Escape` row would swallow Escape for every application --
      #      unusable in a terminal or editor. The common `bind` rows carry a
      #      modifier for that reason. Hardware `bindl` rows use `NONE`
      #      because those keys have none; bare Escape stays in resize only.
      #
      # These are MOVED, not copied, out of the top-level lists above.
      # check_key_binding_conflicts (parse_config.c:3279-3345) calls a chord
      # conflicting when either side is `common` (`any_common`), and the same
      # test covers mousebind and bindl. A copy left in `default` warns at
      # parse time unless both rows are `bindc`. Home Manager writes
      # `keymode = common` and then these bind / bindl / mousebind lines.
      keymode.common.bind = [
        # mango hot-reloads config.conf; without a bind there is no way to ask
        # for it after editing the file by hand.
        "SUPER+ALT,R,reload_config"
        "SUPER,Q,killclient"
        # The safety net: reachable from any mode, including one this config no
        # longer defines. Not `NONE,Escape` -- see point 3 above.
        "SUPER,Escape,setkeymode,default"
      ];

      # Same chords as the old top-level mousebind. Not repeated in default.
      keymode.common.mousebind = [
        "SUPER,btn_left,moveresize,curmove"
        "SUPER,btn_right,moveresize,curresize"
      ];

      # Hardware keys stay available in every keymode, including while locked.
      # Bare Escape stays out of common; only resize mode binds it.
      keymode.common.bindl = [
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
        "NONE,H,resizewin,-10,+0"
        "NONE,Left,resizewin,-10,+0"
        "NONE,J,resizewin,+0,+10"
        "NONE,Down,resizewin,+0,+10"
        "NONE,K,resizewin,+0,-10"
        "NONE,Up,resizewin,+0,-10"
        "NONE,L,resizewin,+10,+0"
        "NONE,Right,resizewin,+10,+0"
        "NONE,Escape,setkeymode,default"
      ];
    };

    # Mango has no column consume/expel, first/last-column movement,
    # preset column/window heights, center-visible-columns, floating/tiling
    # focus switching, or compositor screenshot dispatcher. Shortcut
    # inhibition is supported: allow_shortcuts_inhibit defaults to on.
    # Those missing actions are intentionally not recreated with unrelated
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
