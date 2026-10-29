{ inputs, ... }:

{
  imports = [ inputs.mango.nixosModules.mango ];

  programs.mango = {
    enable = true;
  };

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

  # Portal packages are composed upstream; session support deduplicates the
  # generated D-Bus service directories without replacing the portal list.
}
