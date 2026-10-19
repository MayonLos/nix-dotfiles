{ hostFacts, ... }:

let
  desktop = {
    primaryOutput = hostFacts.display.name;
  };
in

{
  # Mango's locked module supplies its wlroots capture backend and default
  # routing; common portal packages and the keyring live in portal-common.nix.
  xdg.portal = {
    config.mango = {
      # Mango already routes capture through wlr; it does not implement the
      # Mutter ScreenCast interface used by GNOME. Keep only additional keys.
      # The locked GNOME backend delegates FileChooser to Nautilus. This
      # desktop uses Thunar, so GTK is the functioning chooser without adding
      # a second FileManager1 owner. GTK 3 cannot match fractional output DPI.
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
      "org.freedesktop.impl.portal.Settings" = "gnome";
      "org.freedesktop.impl.portal.OpenURI" = "gtk";
    };

    config.common.default = "gnome";

    # xdg-desktop-portal-wlr is started with an explicit
    # `--config=<generated ini>` (this option is what generates it), and
    # xdpw's init_config() skips its own $XDG_CONFIG_HOME search entirely
    # when --config is given. So a hand-written
    # ~/.config/xdg-desktop-portal-wlr/config is silently never read; it has
    # to go here.
    #
    # Historical failure: xdpw's external output chooser was unavailable.
    # dmenu is now present only when Xorg is selected, but it is not a native
    # Wayland output chooser. Keep capture independent of that optional stack.
    # slurp selects regions rather than choosing an output.
    #
    # One output, so skip the chooser rather than install a picker to answer a
    # question with one possible answer. Revisit if a second output appears.
    wlr.settings.screencast = {
      output_name = desktop.primaryOutput;
      chooser_type = "none";
      max_fps = 60;
    };
  };
}
