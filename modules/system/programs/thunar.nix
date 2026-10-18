{
  pkgs,
  ...
}:

{
  programs = {
    thunar = {
      enable = true;
      plugins = [
        (pkgs.thunar-archive-plugin.overrideAttrs (oldAttrs: {
          nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
          postInstall = (oldAttrs.postInstall or "") + ''
            # Thunar searches its own compiled libexec path. Xarchiver's tap
            # is already wrapped by wrapGAppsHook3, so wrap that executable
            # rather than text-patching it. Its script invokes xarchiver by
            # name; provide the GUI's PATH independently of Home Manager.
            mkdir -p "$out/libexec/thunar-archive-plugin"
            makeWrapper ${pkgs.xarchiver}/libexec/thunar-archive-plugin/xarchiver.tap \
              "$out/libexec/thunar-archive-plugin/xarchiver.tap" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.xarchiver ]}
          '';
        }))
        pkgs.thunar-volman
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
