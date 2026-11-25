{ pkgs, ... }:
{
  # Luciole is installed for the Umbriel session; the Mango session keeps
  # Thunar as the default file manager (MIME defaults are user-wide).
  home.packages = [ pkgs.local.noctaliaDesktop.luciole ];
}
