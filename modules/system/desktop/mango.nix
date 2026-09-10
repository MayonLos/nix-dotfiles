{ inputs, ... }:

{
  imports = [ inputs.mango.nixosModules.mango ];

  programs.mango.enable = true;

  # Deliberately no `xdg.portal.extraPortals` override here. mango's module
  # lists xdg-desktop-portal-wlr and -gtk, and `xdg.portal.wlr.enable` adds wlr
  # a second time, so the merged list holds duplicates. They are the *same*
  # derivations, which collapse to one store path in the union that
  # services.dbus.packages and systemd.packages build from -- one service file,
  # one process, no second claimant for a D-Bus name.
  #
  # Rewriting that list by hand is what breaks things: the entries come from
  # three different modules (mango's, xdg.portal.wlr, and the gnome backend and
  # keyring that desktop/xdg.nix asks for by name), and an mkForce that forgets
  # any one of them silently disables a portal. Add to the list, never replace
  # it.
}
