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
  alphaColor = value: alpha: "0x${lib.removePrefix "#" value}${alpha}";
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
  sharedSessionVariables = import ./session-environment.nix {
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
      # Keep pointer discovery and activation semantics; typing still hides it.
      cursor_hide_timeout = 0;
      focus_on_activate = 0;
      warp_cursor = 1;

      # Mango 0.18.3 has no ext-background-effect-v1. Its native layer blur
      # supplies the bar/Dock frost; ordered rules below restrict its scope.
      blur = 1;
      blur_layer = 1;
      blur_optimized = 1;
      blur_params_radius = 5;
      blur_params_num_passes = 2;
      layer_animations = 0;
      shadows = 1;
      layer_shadows = 0;
      # Only floating windows need elevation; focus is the native 2 px blue border.
      shadow_only_floating = 1;
      shadows_size = 10;
      shadows_blur = 20;
      shadows_position_x = 0;
      shadows_position_y = 6;
      shadows_color = alphaColor palette.black "52";

      # A light native dim overlay distinguishes inactive clients without transparency.
      # Fullscreen is exempt upstream; 0.18.3 has no per-window no_dim rule.
      dim_enable = 1;
      dim_focused_color = alphaColor palette.black "00";
      dim_unfocused_color = alphaColor palette.black "10";

      # Include the fallback canvas and drag/split hints in the same palette.
      root_color = color palette.bg;
      drop_color = "0x${lib.removePrefix "#" palette.blue}80";
      split_color = color palette.cyan;
      border_px = 2;
      border_color = "${color palette.surface}";
      focus_color = "${color palette.blue}";
      urgent_color = "${color palette.red}";
      scratchpad_color = "${color palette.blue}";
      global_color = "${color palette.blue}";
      overlay_color = "${color palette.blue}";
      maximized_screen_color = "${color palette.blue}";
      border_radius = 10;
      gap_inner_horizontal = 8;
      gap_inner_vertical = 8;
      gap_outer_horizontal = 12;
      gap_outer_vertical = 12;
      smart_gaps = 0;
      no_border_when_single = 0;
      no_radius_when_single = 0;
      monocle_no_border = 0;
      monocle_no_gap = 0;

      animations = if reducedMotion then 0 else 1;
      animation_type_open = "zoom";
      animation_type_close = "zoom";
      animation_fade_in = 1;
      animation_fade_out = 1;
      fade_in_begin_opacity = 0.5;
      fade_out_begin_opacity = 0.5;
      zoom_initial_ratio = 0.96;
      zoom_end_ratio = 0.98;
      animation_duration_move = 180;
      animation_duration_open = 180;
      animation_duration_tag = 180;
      animation_duration_close = 160;
      animation_duration_focus = 0;
      # One ease-out curve across opens/closes/moves/tags; no overshoot.
      # Focus still responds immediately and reducedMotion disables animations.
      animation_curve_open = "0.16,1.0,0.3,1.0";
      animation_curve_move = "0.16,1.0,0.3,1.0";
      animation_curve_tag = "0.16,1.0,0.3,1.0";
      animation_curve_close = "0.16,1.0,0.3,1.0";
      animation_curve_focus = "0.16,1.0,0.3,1.0";
      animation_curve_opacity_fade_in = "0.16,1.0,0.3,1.0";
      animation_curve_opacity_fade_out = "0.16,1.0,0.3,1.0";
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
      # A larger centered preview makes titles/content readable on 1.5x DPI.
      overcircle_center_ratio = 0.60;
      jump_labels = "HJKLASDFGQWERTYUIOPZXCVBNM";
      # Preserve numbered tag navigation without wrapping at either end.
      tag_carousel = 0;
      overview_gap_inner = 16;
      overview_gap_outer = 32;
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
      tab_bar_decorate_font_desc = "${palette.fonts.mono} 10.5";
      tab_bar_decorate_fg_color = "${color palette.fg}";
      tab_bar_decorate_bg_color = "${color palette.deep}";
      tab_bar_decorate_focus_fg_color = "${color palette.blue}";
      tab_bar_decorate_focus_bg_color = "${color palette.selection}";
      tab_bar_decorate_border_color = "${color palette.surface}";
      tab_bar_decorate_border_width = 1;
      tab_bar_decorate_corner_radius = 8;
      tab_bar_decorate_padding_x = 8;
      tab_bar_decorate_padding_y = 4;
      group_bar_height = 32;
      group_bar_close_button_enable = 0;
      group_bar_button_size = 16;
      group_bar_button_margin = 8;
      group_bar_button_color = color palette.red;
      group_bar_decorate_font_desc = "${palette.fonts.mono} 10.5";
      group_bar_decorate_fg_color = "${color palette.fg}";
      group_bar_decorate_bg_color = "${color palette.deep}";
      group_bar_decorate_focus_fg_color = "${color palette.blue}";
      group_bar_decorate_focus_bg_color = "${color palette.selection}";
      group_bar_decorate_border_color = "${color palette.surface}";
      group_bar_decorate_border_width = 1;
      group_bar_decorate_corner_radius = 8;
      group_bar_decorate_padding_x = 8;
      group_bar_decorate_padding_y = 4;
      jump_label_decorate_font_desc = "${palette.fonts.mono} Bold 12";
      jump_label_decorate_fg_color = "${color palette.brightFg}";
      jump_label_decorate_bg_color = "${color palette.deep}";
      jump_label_decorate_focus_fg_color = "${color palette.blue}";
      jump_label_decorate_focus_bg_color = "${color palette.selection}";
      jump_label_decorate_border_color = "${color palette.surface}";
      jump_label_decorate_border_width = 1;
      jump_label_decorate_corner_radius = 8;
      jump_label_decorate_padding_x = 8;
      jump_label_decorate_padding_y = 4;

      # overcircle/switcher titles otherwise inherit upstream green/Gruvbox.
      # Use the same type, outline and focused blue as the monocle tab bar.
      title_message_bar_height = 48;
      title_message_bar_gap = 12;
      title_message_bar_decorate_font_desc = "${palette.fonts.mono} 10.5";
      title_message_bar_decorate_fg_color = color palette.fg;
      title_message_bar_decorate_bg_color = color palette.deep;
      title_message_bar_decorate_focus_fg_color = color palette.blue;
      title_message_bar_decorate_focus_bg_color = color palette.selection;
      title_message_bar_decorate_border_color = color palette.border;
      title_message_bar_decorate_border_width = 1;
      title_message_bar_decorate_corner_radius = 8;
      title_message_bar_decorate_padding_x = 8;
      title_message_bar_decorate_padding_y = 4;

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
      # An 8px grab strip is easier than the 2px outline without consuming
      # the default 10px of application edge controls. Super+R stays available.
      enable_border_resize = 1;
      border_resize_size = 8;
      drag_tile_to_tile = 1;
      enable_floating_snap = 1;
      snap_distance = 12;

      # Rules apply in order: transparent clients and unrelated layer surfaces
      # stay unblurred; only the translucent bar/Dock opt back in.
      layer_rule = [
        "layer_name:.*,no_blur:1"
        "layer_name:^noctalia-(bar-.*|dock)$,no_blur:0,no_animation:1,no_shadow:1"
        "layer_name:^(noctalia-system-menu|noctalia-plugin:nix-dotfiles/desktop-menus:preview)$,no_blur:0,no_animation:1,no_shadow:1"
        "layer_name:^noctalia-plugin:nix-dotfiles/launchpad:drawer$,no_blur:0,no_animation:1,no_shadow:1"
        "layer_name:^noctalia-(panel|attached-panel|notification|osd|window-switcher|panel-click-shield)$,no_animation:1,no_blur:1,no_shadow:1"
        "layer_name:^noctalia-(screenshot-region|annotate)$,no_animation:1,no_blur:1,no_shadow:1"
      ];

      # Single rule owner. Keep app destinations opt-in to preserve current tags.
      window_rule = import ./mango/window-rules.nix { inherit lib; };
      # Mango 0.18.3 supports 0/1/2; 2 gates tearing to fullscreen.
      # The rule table opts normal clients out and games in.
      allow_tearing = 2;

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
      key_mode = {
        common = {
          bind = commonBinds;

          # Same chords as the old top-level mousebind. Not repeated in default.
          mousebind = [
            "SUPER,btn_left,moveresize,curmove"
            "SUPER,btn_right,moveresize,curresize"
          ];

          # Hardware keys stay available in every key_mode, including while locked.
          # Bare Escape stays out of common; only resize mode binds it.
          bindl = hardwareBinds;

        };

        resize.bind = resizeBinds;
      };

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
