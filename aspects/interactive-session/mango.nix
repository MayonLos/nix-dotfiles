{ palette }:
{
  config,
  hostFacts,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (hostFacts) display;
  reducedMotion = palette.reducedMotion or false;
  color = value: "0x${lib.removePrefix "#" value}ff";
  helpPath = "${config.xdg.dataHome}/mango/keybindings.txt";
  renderBind =
    row:
    if lib.hasInfix ",__MANGO_HELP__" row then
      lib.replaceStrings
        [ ",__MANGO_HELP__" ]
        [
          ",${lib.getExe pkgs.kitty} --title Mango-keybindings ${pkgs.less}/bin/less ${lib.escapeShellArg helpPath}"
        ]
        row
    else
      row;
  sharedSessionVariables = import ../../lib/session-environment.nix {
    inherit lib;
  } config.systemd.user.sessionVariables;
  inherit (import ./mango/keybinds.nix { inherit lib pkgs display; })
    defaultBinds
    commonBinds
    hardwareBinds
    resizeBinds
    gestures
    helpText
    ;
in
{
  imports = [ inputs.mango.hmModules.mango ];
  xdg.dataFile."mango/keybindings.txt".text = helpText;

  wayland.windowManager.mango = {
    enable = true;

    # Mango's systemd hook imports dynamic session variables and starts
    # mango-session.target. The static whitelist below is available to Mango's
    # early target request and to its HM autostart synchronization.
    systemd.enable = true;

    settings = {
      monitor_rule = [
        "name:^${display.name}$,width:${toString display.width},height:${toString display.height},refresh:${toString display.refresh},x:0,y:0,scale:${toString display.scale},vrr:1"
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
      # exactly what `Xft.dpi: 144` in xresources.nix is for, and it is
      # already merged into this server (`xrdb -query` returns it). The two
      # settings are a pair; neither works alone.
      xwayland_ignore_scale = if display.scale > 1 then 1 else 0;

      # mango is exec'd straight from the session desktop file, not through a
      # login shell, so it inherits none of Home Manager's session variables --
      # niri got them because niri-session is a shell wrapper that sources
      # hm-session-vars.sh. Selected static session variables are copied from
      # systemd.user.sessionVariables so Mango and its children see the same
      # safe shared values. `env=` is setenv'd into the compositor's own
      # process at config-parse time (src/config/parse_config.c:335).
      #
      # The one that bites hardest is NIXOS_OZONE_WL: the nixpkgs Electron
      # wrappers add `--ozone-platform=wayland` only when it is set, so without
      # it every Electron app lands on XWayland and renders visibly blurry at
      # this 1.5x scale. The shared session variable declaration remains the
      # source of truth.
      #
      # Values needing shell expansion are dropped: mango expands `~/` and
      # nothing else, so a `${...}` or `$(...)` would be set as that literal
      # string. TMUX_TMPDIR is the one that hits this today; shells still get
      # it from hm-session-vars.sh, which is where it matters. Mango also caps
      # values at 255 bytes (including the generated leading space); long
      # values such as FZF_DEFAULT_OPTS stay in the
      # shell environment rather than making the compositor config invalid.
      env = lib.mapAttrsToList (n: v: "${n},${v}") (
        lib.filterAttrs (n: v: builtins.stringLength " ${n},${v}" <= 255) sharedSessionVariables
      );

      # Carried over from niri's `cursor` block. cursor_hide_on_keypress is
      # mango's spelling of niri's `hide-when-typing`; there is no global
      # prefer-no-csd equivalent (mango's allow_csd is a window_rule field only,
      # and it does not ask clients for decorations anyway).
      cursor_theme = palette.cursor.name;
      cursor_size = palette.cursor.size;
      cursor_hide_on_keypress = 1;

      # Noctalia owns layer shadows/animations. Its reading panels are opaque;
      # client blur remains available for apps that explicitly use transparency.
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
      # Elevation belongs to floating tools/dialogs. Tiled documents use the
      # existing border/focus colours instead of a shadow in every narrow gap.
      shadow_only_floating = 1;
      shadows_size = 10;
      shadows_blur = 20;
      shadows_position_x = 0;
      shadows_position_y = 5;
      shadows_color = "0x00000059";

      # Comparing multiple documents should not change their text contrast.
      # The accent border identifies focus without tinting the other clients.
      dim_enable = 0;
      dim_focused_color = "0x00000000";
      dim_unfocused_color = "0x00000010";

      border_px = 2;
      border_color = "${color palette.border}";
      focus_color = "${color palette.blue}";
      urgent_color = "${color palette.red}";
      scratchpad_color = "${color palette.purple}";
      global_color = "${color palette.cyan}";
      overlay_color = "${color palette.purple}";
      maximized_screen_color = "${color palette.blue}";
      border_radius = 12;
      gap_inner_horizontal = 6;
      gap_inner_vertical = 6;
      gap_outer_horizontal = 10;
      gap_outer_vertical = 10;
      smart_gaps = 0;
      no_border_when_single = 0;

      animations = if reducedMotion then 0 else 1;
      animation_type_open = "zoom";
      animation_type_close = "zoom";
      animation_fade_in = 1;
      animation_fade_out = 1;
      fade_in_begin_opacity = 0.5;
      fade_out_begin_opacity = 0.5;
      zoom_initial_ratio = 0.94;
      zoom_end_ratio = 0.96;
      animation_duration_move = 160;
      animation_duration_open = 200;
      animation_duration_tag = 220;
      animation_duration_close = 140;
      animation_duration_focus = 0;
      animation_curve_open = "0.46,1.0,0.29,0.99";
      animation_curve_move = "0.46,1.0,0.29,0.99";
      animation_curve_tag = "0.46,1.0,0.29,0.99";
      animation_curve_close = "0.46,1.0,0.29,0.99";
      animation_curve_focus = "0.46,1.0,0.29,0.99";
      animation_curve_opacity_fade_in = "0.46,1.0,0.29,0.99";
      # Was "0.5,0.5,0.5,0.5" -- a bezier straight down the diagonal, i.e.
      # constant velocity. Every other curve here, including its own
      # opafadein counterpart, eases; the fade-out was the one motion in the
      # compositor that did not.
      animation_curve_opacity_fade_out = "0.46,1.0,0.29,0.99";
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
      idle_inhibit_when_fullscreen = 1;

      new_is_master = 1;
      default_master_factor = 0.55;
      default_master_count = 1;
      tag_num = 9;
      # Layout defaults describe activities, not app-id destinations. Users can
      # still move any application to any tag and change its layout.
      tag_rule = [
        "id:*,layout_name:tile"
        "id:0,layout_name:scroller,scroller_default_proportion:0.65"
        "id:1,layout_name:tile,master_factor:0.60"
        "id:2,layout_name:scroller,scroller_default_proportion:0.80"
        "id:4,layout_name:monocle"
        "id:5,layout_name:tile,master_factor:0.65"
        "id:6,layout_name:monocle"
        "id:8,layout_name:monocle"
      ];
      overview_gap_inner = 12;
      overview_gap_outer = 24;
      scratchpad_width_ratio = 0.78;
      scratchpad_height_ratio = 0.78;
      single_scratchpad = 1;
      scratchpad_cross_monitor = 1;
      special_dim = 0.32;
      special_gap_inner_horizontal = 8;
      special_gap_inner_vertical = 8;
      special_gap_outer_horizontal = 20;
      special_gap_outer_vertical = 20;
      # switch_layout walks only this list. The three names are layouts[]
      # entries in the pinned arrange.c: tile, scroller, monocle.
      circle_layout = "tile,scroller,monocle";

      # Tabbed monocle exposes the full-screen stack as clickable tabs;
      # deck_tab_mode stays at its default because deck is outside circle_layout.
      monocle_tab_mode = 1;
      tab_bar_height = 32;
      tab_bar_decorate_font_desc = "${palette.fonts.sans} 10";
      tab_bar_decorate_fg_color = "${color palette.fg}";
      tab_bar_decorate_bg_color = "${color palette.deep}";
      tab_bar_decorate_focus_fg_color = "${color palette.black}";
      tab_bar_decorate_focus_bg_color = "${color palette.blue}";
      tab_bar_decorate_border_color = "${color palette.border}";
      tab_bar_decorate_border_width = 1;
      tab_bar_decorate_corner_radius = 8;
      tab_bar_decorate_padding_x = 6;
      tab_bar_decorate_padding_y = 2;
      group_bar_decorate_font_desc = "${palette.fonts.sans} 10";
      group_bar_decorate_fg_color = "${color palette.fg}";
      group_bar_decorate_bg_color = "${color palette.deep}";
      group_bar_decorate_focus_fg_color = "${color palette.black}";
      group_bar_decorate_focus_bg_color = "${color palette.purple}";
      group_bar_decorate_border_color = "${color palette.border}";
      group_bar_decorate_border_width = 1;
      group_bar_decorate_corner_radius = 8;
      group_bar_decorate_padding_x = 6;
      group_bar_decorate_padding_y = 2;
      jump_label_decorate_font_desc = "${palette.fonts.sans} 10";
      jump_label_decorate_fg_color = "${color palette.brightFg}";
      jump_label_decorate_bg_color = "${color palette.selection}";
      jump_label_decorate_focus_fg_color = "${color palette.black}";
      jump_label_decorate_focus_bg_color = "${color palette.blue}";
      jump_label_decorate_border_color = "${color palette.border}";
      jump_label_decorate_border_width = 1;
      jump_label_decorate_corner_radius = 6;
      jump_label_decorate_padding_x = 5;
      jump_label_decorate_padding_y = 2;

      repeat_rate = 30;
      repeat_delay = 400;
      numlock_on = 1;
      xkb_rules_layout = "us";
      tap_to_click = 1;
      trackpad_natural_scrolling = 1;
      trackpad_disable_while_typing = 1;
      trackpad_scroll_method = 1;
      trackpad_click_method = 1;
      trackpad_middle_button_emulation = 1;
      trackpad_accel_profile = 2;
      button_map = 0;
      sloppy_focus = 1;

      # 4 selects the nearest corner from the press point. 0 leaves the
      # pointer where it is. Pinned defaults are the southeast corner and a
      # warp (pointer.c treats 0 as "do not warp", not as "no corner").
      drag_corner = 4;
      drag_warp_cursor = 0;
      enable_floating_snap = 1;
      snap_distance = 12;

      # Pinned Mango supports layer_rule. Noctalia owns its animations/shadows;
      # these namespaces come from its pinned C++ layer-surface constructors.
      # Keep the global layer effects off too: this is not an instruction to
      # animate or blur every surface, nor a promise of compositor bar blur.
      layer_rule = [
        "layer_name:^noctalia-(bar-.*|panel|attached-panel|notification|osd|window-switcher|panel-click-shield)$,no_animation:1,no_shadow:1"
        "layer_name:^noctalia-(screenshot-region|annotate)$,no_animation:1,no_blur:1,no_shadow:1"
      ];

      # Exact app-id/title rules; leave transient-parent detection and size hints
      # intact. Offsets are percentages of remaining space, not pixel positions.
      window_rule = [
        "is_floating:1,width:0.60,height:0.72,animation_type_open:fade,animation_type_close:fade,app_id:^swayimg$"
        "is_floating:1,animation_type_open:fade,animation_type_close:fade,app_id:^thunar$,title:^(Rename|重命名)"
        # Global means visible across this output's tags, not forced above
        # fullscreen games. Super+Alt+G opts into overlay for the focused PiP.
        "is_floating:1,is_global:1,is_open_silent:1,width:480,height:270,offset_x:85,offset_y:80,animation_type_open:fade,animation_type_close:fade,app_id:^[Ff]irefox$,title:^Picture-in-Picture$"
        # blueman-manager, nm-connection-editor and org.gnome.Calculator were
        # in this alternation and are installed nowhere -- not on PATH, not in
        # any module. Template leftovers. Add an app_id back when the program
        # that carries it actually arrives, not before: a rule that cannot
        # match is indistinguishable from one that is broken.
        "is_floating:1,width:0.62,height:0.68,animation_type_open:fade,animation_type_close:fade,app_id:^xdg-desktop-portal-gtk$"
        # No polkit rule. This host runs no standalone polkit GUI agent --
        # noctalia's built-in one is the only authentication agent (see
        # noctalia.nix's `polkit_agent`), and it draws in the shell rather than
        # opening a top-level window, so nothing can ever carry a `polkit-*` or
        # `org.freedesktop.PolicyKit*` app_id here.
        # `.Settings` was never an app_id. Measured with `mmsg get all-clients`
        # while the window was open: it reports `dev.noctalia.Noctalia`, and the
        # window came up tiled at 936x1010 instead of its requested floating
        # geometry. Keep the observed id; sizes now follow each output.
        "is_floating:1,width:0.68,height:0.82,animation_type_open:fade,animation_type_close:fade,app_id:^dev\\.noctalia\\.Noctalia$"
        "vrr_only_fullscreen:1,no_radius:1,no_animation:1,app_id:^steam_app_"
        # Kitty's own background is opaque. Keep client glyphs/content opaque
        # too; focus dim is a separate compositor overlay. Include named tools.
        "focused_opacity:1.0,unfocused_opacity:1.0,app_id:^(kitty|mayon-scratch|mayon-files|mayon-monitor)$"
        "is_named_scratchpad:1,width:0.78,height:0.78,animation_type_open:fade,animation_type_close:fade,app_id:^mayon-scratch$"
        "is_named_scratchpad:1,width:0.78,height:0.78,animation_type_open:fade,animation_type_close:fade,app_id:^mayon-files$"
        "is_named_scratchpad:1,width:0.72,height:0.74,animation_type_open:fade,animation_type_close:fade,app_id:^mayon-monitor$"
      ];

      # Launches, Noctalia shell controls, tag navigation, and dwm-style
      # master-stack operations.
      bind = map renderBind defaultBinds;

      # Default-mode gestures. none is a real modifier token and sets no
      # bits. Four-finger left/right switch occupied tags; both vertical
      # swipes toggle overview. Three-finger swipes are focusdir.
      gesturebind = gestures;

      # Binds that stay live in EVERY key_mode. Three facts forced this block
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
      # `key_mode = common` and then these bind / bindl / mousebind lines.
      key_mode.common.bind = commonBinds;

      # Same chords as the old top-level mousebind. Not repeated in default.
      key_mode.common.mousebind = [
        "SUPER,btn_left,moveresize,curmove"
        "SUPER,btn_right,moveresize,curresize"
      ];

      # Hardware keys stay available in every key_mode, including while locked.
      # Bare Escape stays out of common; only resize mode binds it.
      key_mode.common.bindl = hardwareBinds;

      key_mode.resize.bind = resizeBinds;
    };

    # Mango has no column consume/expel, first/last-column movement,
    # preset column/window heights, center-visible-columns, floating/tiling
    # focus switching, or compositor screenshot dispatcher. Shortcut
    # inhibition is supported: allow_shortcuts_inhibit defaults to on.
    # Those missing actions are intentionally not recreated with unrelated
    # commands.

    # Keep this non-empty for Mango HM's environment/target synchronization
    # hook. Mango's C startup path also requests mango-session.target before
    # exec_once, so target startup does not depend on this hook winning a race.
    # Noctalia itself is owned by its systemd user unit.
    autostart_sh = ":";
    extraConfig = "";
  };
}
