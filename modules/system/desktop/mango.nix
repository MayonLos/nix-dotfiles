{ inputs, ... }:

{
  imports = [ inputs.mango.nixosModules.mango ];

  programs.mango.enable = true;

  # mango's module turns on services.graphical-desktop, and
  # nixos/modules/services/misc/graphical-desktop.nix then sets
  # `services.speechd.enable = lib.mkDefault true`. That drags in
  # speech-dispatcher and, behind it, mbrola-voices -- 630 MB of text-to-speech
  # voice data for a screen reader nothing here uses. It is a mkDefault, so one
  # plain assignment reclaims it.
  #
  # The only thing that stops working is "read aloud" in browsers. Flip this
  # back if that is ever wanted.
  services.speechd.enable = false;

  # Deliberately no `xdg.portal.extraPortals` override here. mango's module
  # lists xdg-desktop-portal-wlr and -gtk, and `xdg.portal.wlr.enable` adds wlr
  # a second time, so the merged list holds duplicates. They are the *same*
  # derivation, so only one owner ends up on the bus and it is the right one --
  # but dbus-broker does notice and logs `Ignoring duplicate name
  # 'org.freedesktop.impl.portal.desktop.wlr'` once per extra copy at session
  # start. Cosmetic, and not the failure desktop/xdg.nix's comment warns about
  # (that was two *different* backends fighting over one name).
  #
  # Rewriting that list by hand is what breaks things: the entries come from
  # three different modules (mango's, xdg.portal.wlr, and the gnome backend and
  # keyring that desktop/xdg.nix asks for by name), and an mkForce that forgets
  # any one of them silently disables a portal. Add to the list, never replace
  # it.
}
