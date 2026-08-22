{
  # A trail between the old and new cursor position. Purely cosmetic, and the
  # one thing in the appearance group worth turning off first if the terminal
  # ever struggles: it repaints on every cursor move.
  #
  # Smooth scrolling used to live here as neoscroll; snacks.nvim's `scroll`
  # module replaced it — see snacks.nix.
  plugins.smear-cursor = {
    enable = true;

    settings = {
      stiffness = 0.8;
      trailing_stiffness = 0.6;
      distance_stop_animating = 0.5;
      # foot renders at 165 Hz; matching it keeps the trail smooth without
      # spending frames the compositor will drop anyway.
      time_interval = 7;
    };
  };
}
