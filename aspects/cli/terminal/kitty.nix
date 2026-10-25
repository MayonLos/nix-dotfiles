{ palette }:
{ lib, pkgs, ... }:
let
  ansi = import ../../appearance/appearance/ansi.nix palette;
  ansiConfig = lib.concatStringsSep "\n" (
    lib.imap0 (index: color: "color${toString index} ${color}") ansi
  );
  tabBar = import ./tab-bar.nix { inherit palette; };
in
{
  home.packages = [ pkgs.kitty ];

  # This aspect is the sole renderer for kitty.conf. Noctalia's Kitty template
  # must be disabled for the selected user so it cannot rewrite or include a
  # second palette file at runtime.
  xdg.configFile."kitty/kitty.conf".text = ''
    # Managed by Den's command-line Kitty aspect.

    font_family ${palette.fonts.mono}
    font_size 11.0
    # Shape code consistently even when the block cursor crosses a ligature.
    disable_ligatures never
    modify_font cell_height 108%
    # Maple 7.9: programming ligatures, normalized symbols, dotted zero.
    font_features MapleMono-NF-CN-Regular +calt +cv01 +zero
    font_features MapleMono-NF-CN-Bold +calt +cv01 +zero
    # Fontconfig may choose SemiBold for Kitty's automatic bold face.
    font_features MapleMono-NF-CN-SemiBold +calt +cv01 +zero
    font_features MapleMono-NF-CN-Italic +calt +cv01 +zero
    font_features MapleMono-NF-CN-BoldItalic +calt +cv01 +zero
    font_features MapleMono-NF-CN-SemiBoldItalic +calt +cv01 +zero

    background_opacity 1.0
    background ${palette.deep}
    foreground ${palette.brightFg}

    cursor_shape beam
    cursor_beam_thickness 1.5
    cursor_blink_interval ${if palette.reducedMotion or false then "0" else "0.5"}
    # Only animate cursor jumps that pause briefly; honor the shared motion preference.
    cursor_trail ${if palette.reducedMotion or false then "0" else "1"}
    cursor_trail_decay 0.08 0.16
    cursor_trail_start_threshold 4
    cursor_trail_color ${palette.blue}
    cursor ${palette.brightFg}
    cursor_text_color ${palette.deep}

    selection_background ${palette.selection}
    selection_foreground ${palette.brightFg}

    # Match the editor's quiet tabs without adding a second project manager.
    tab_bar_min_tabs 2
    tab_bar_style custom
    tab_title_template "{index}: {title}"
    active_tab_foreground ${palette.brightFg}
    active_tab_background ${palette.deep}
    active_tab_font_style bold
    inactive_tab_foreground ${palette.fg}
    inactive_tab_background ${palette.deep}
    tab_bar_background ${palette.deep}

    undercurl_style thick-sparse

    scrollback_lines 5000
    wheel_scroll_multiplier 5.0

    hide_window_decorations yes
    # Leave a small breathing space; Neovim synchronizes OSC 11 to Normal.
    window_padding_width 4
    placement_strategy top-left
    # Match the sidebar/statusline cells at fractional-scale grid remainders.
    padding_fill_strategy neighboring_cell
    # Ask before closing a window with a running foreground task.
    confirm_os_window_close -1
    enable_audio_bell no
    visual_bell_duration ${if palette.reducedMotion or false then "0" else "0.1"}
    bell_on_tab yes
    shell_integration enabled

    map ctrl+shift+o open_url_with_hints
    map ctrl+shift+page_up scroll_page_up
    map ctrl+shift+page_down scroll_page_down
    map ctrl+shift+home scroll_home
    map ctrl+shift+end scroll_end
    map ctrl+equal change_font_size all +1.0
    map ctrl+minus change_font_size all -1.0
    map ctrl+0 change_font_size all 0

    ${ansiConfig}
  '';

  xdg.configFile."kitty/tab_bar.py".text = tabBar;
}
