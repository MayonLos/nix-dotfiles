{ palette }:
{ lib, pkgs, ... }:
let
  ansi = import ../appearance/ansi.nix palette;
  ansiConfig = lib.concatStringsSep "\n" (
    lib.imap0 (index: color: "color${toString index} ${color}") ansi
  );
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
    disable_ligatures cursor

    background_opacity 1.0
    background ${palette.bg}
    foreground ${palette.fg}

    cursor_shape beam
    cursor_beam_thickness 1.5
    cursor_blink_interval ${if palette.reducedMotion or false then "0" else "0.5"}
    cursor ${palette.brightFg}
    cursor_text_color ${palette.bg}

    selection_background ${palette.selection}
    selection_foreground ${palette.brightFg}

    # Match the editor's quiet tabs without adding a second project manager.
    tab_bar_min_tabs 2
    tab_bar_style separator
    tab_separator " │ "
    tab_title_template "{index}: {title}"
    active_tab_foreground ${palette.brightFg}
    active_tab_background ${palette.surface}
    active_tab_font_style bold
    inactive_tab_foreground ${palette.muted}
    inactive_tab_background ${palette.deep}
    tab_bar_background ${palette.deep}

    scrollback_lines 5000
    wheel_scroll_multiplier 5.0

    hide_window_decorations yes
    window_padding_width 8
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
}
