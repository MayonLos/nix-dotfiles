{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Keep the upstream policy includes and activation precedence, but merge
  # explicit service directories by bus name. Standard XDG session directories
  # already expose system.path; registering its services again logs duplicates.
  # force: This feature owns the deduplicated form of the upstream D-Bus config.
  environment.etc."dbus-1".source = lib.mkForce (
    (pkgs.makeDBusConf.override {
      inherit (config.services.dbus) apparmor;
      dbus = config.services.dbus.dbusPackage;
      suidHelper = "${config.security.wrapperDir}/dbus-daemon-launch-helper";
      serviceDirectories = lib.unique config.services.dbus.packages;
    }).overrideAttrs
      (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
        buildCommand = old.buildCommand + ''
          python3 ${./deduplicate-dbus.py} "$out" ${config.system.path}
        '';
      })
  );

  # GTK provides Settings without requiring a Mutter session. Capture routing
  # belongs to each session implementation; retain the keyring Secret backend.
  services.gnome.gnome-keyring.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
  };
}
