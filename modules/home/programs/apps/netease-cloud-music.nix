{ pkgs, ... }:
{
  # NetEase Cloud Music. The download page offers a Windows .exe; the official
  # Linux .deb stopped at 1.2.1 in 2019 and its sign-in no longer works. This is
  # gmg137's third-party GTK4 client against the same web API -- native, rather
  # than running the Windows build under Wine. That build is Electron, and Wine
  # plus Electron plus audio is a worse trade than an unofficial client.
  #
  # The cost is the usual one for a reimplemented API: it breaks whenever
  # NetEase changes it, and VIP or otherwise DRM-protected tracks will not play.
  # If that becomes the common case, the answer is the web player in Zen, not
  # Wine.
  #
  # `pkgs` rather than pkgs-unstable: both channels are on 2.5.3.
  #
  # Nothing to wrap here. nixpkgs' own wrapper already sets
  # GST_PLUGIN_SYSTEM_PATH_1_0 (gstreamer + plugins base/good/bad/ugly),
  # GIO_EXTRA_MODULES and the gsettings schema path -- read out of the generated
  # wrapper rather than assumed, because an unwrapped GStreamer app fails by
  # playing silence rather than by erroring.
  #
  # Nothing to theme either. It is GTK4/libadwaita, and base/gtk.nix leaves
  # gtk4.theme null exactly so those applications read the
  # ~/.config/gtk-4.0/gtk.css that noctalia renders. Tier 1 of the two-tier
  # colour rule in the desktop-apps skill, for free.
  #
  # Media keys and noctalia's media widget need no configuration: the binary
  # implements org.mpris.MediaPlayer2.Player.
  #
  # One thing to know if playback ever fails with everything else working: the
  # client honours http_proxy/https_proxy/ALL_PROXY, and NetEase serves China
  # only, so a foreign exit node breaks it. Nothing in this repo exports those
  # in a user session -- modules/system/core/nix.nix sets http_proxy for the nix
  # daemon alone -- so this goes direct unless clash's own rules say otherwise.
  home.packages = [ pkgs.netease-cloud-music-gtk ];
}
