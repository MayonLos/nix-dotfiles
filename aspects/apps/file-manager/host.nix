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

  # gvfsd-metadata handles one journaled Remove per deleted file. Emptying a
  # modpack-sized trash kept it at 100% CPU for minutes, and Thunar's D-Bus calls
  # hit the 25 s timeout. Nothing here relies on metadata writes; D-Bus activation
  # then fails immediately and existing metadata files are left in place.
  systemd.user.units."gvfs-metadata.service".enable = false;
}
