{
  pkgs,
  ...
}:

let
  fileManager = import ./packages.nix { inherit pkgs; };
in
{
  # The locked programs.thunar module has no package option. Reproduce its
  # four registrations for the same tailored package used by HM and D-Bus.
  environment.systemPackages = [ fileManager.thunarWithPlugins ];
  services.dbus.packages = [ fileManager.thunarWithPlugins ];
  systemd.packages = [ fileManager.thunarWithPlugins ];
  programs.xfconf.enable = true;
  programs.dconf.enable = true;

  services = {
    # GVfs pulls in udisks2 itself; Tumbler is the thumbnailer.
    gvfs.enable = true;
    tumbler.enable = true;
  };
}
