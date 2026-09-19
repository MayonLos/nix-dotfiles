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

    dconf.enable = true;
  };

  services = {
    # gvfs pulls in udisks2 itself, and programs.thunar pulls in xfconf --
    # neither needs restating here. tumbler is the thumbnailer, which does.
    gvfs.enable = true;
    tumbler.enable = true;
  };
}
