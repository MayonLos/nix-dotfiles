{ inputs, ... }:

{
  imports = [ inputs.mango.nixosModules.mango ];

  programs.mango.enable = true;

  # Deliberately no `xdg.portal.extraPortals` override here, even though the
  # merged list ends up holding xdg-desktop-portal-gtk twice (niri's module
  # pulls in xdg-desktop-portal-gnome, which drags gtk along; mango's module
  # lists wlr + gtk itself).
  #
  # The duplicate is the *same* derivation, so it collapses to one store path
  # and costs nothing. Forcing a hand-written list instead is what breaks
  # things: `programs.niri.enable` is what puts xdg-desktop-portal-gnome in
  # that list in the first place, and gnome-keyring is in it too -- niri's
  # module routes org.freedesktop.impl.portal.Secret at it. An mkForce that
  # forgets either one silently disables a portal for the *niri* session.
  #
  # The wlr backend mango adds is not redundant: niri implements
  # org.gnome.Mutter.ScreenCast, which is why xdg.nix points its ScreenCast and
  # Screenshot at the gnome backend. mango is plain wlroots and has no such
  # interface, so its screen capture has to go through xdg-desktop-portal-wlr
  # (which mango's own portal config already selects). slurp is on PATH and is
  # the first output chooser that backend looks for.
}
