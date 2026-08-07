{
  pkgs,
  ...
}:

{
  programs = {
    thunar = {
      enable = true;
      plugins = with pkgs; [
        thunar-archive-plugin
        thunar-volman
      ];
    };

    xfconf.enable = true;
    dconf.enable = true;
  };

  services = {
    dbus.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
    udisks2.enable = true;
  };
}
