_: {
  # xdg-desktop-portal-wlr is what serves ScreenCast under mango (niri got this
  # from the GNOME backend via org.gnome.Mutter.ScreenCast, which mango has no
  # equivalent of -- see modules/system/desktop/xdg.nix).
  #
  # Out of the box it asks an external "chooser" which output to capture, and
  # its default chooser list is dmenu-shaped: bemenu, wmenu, wofi, rofi. None of
  # those are installed here, so every one failed and xdpw gave up with
  # "wlroots: no output found" -- which reaches OBS as a screen capture source
  # that stays black, with nothing in OBS's own log to explain it. (slurp is on
  # PATH and does *not* help: it picks a region, not an output.)
  #
  # This host has exactly one output, so the correct answer is to skip the
  # chooser entirely rather than install a picker to answer a question with one
  # possible answer.
  xdg.configFile."xdg-desktop-portal-wlr/config".text = ''
    [screencast]
    output_name=eDP-1
    chooser_type=none
    max_fps=60
  '';
}
