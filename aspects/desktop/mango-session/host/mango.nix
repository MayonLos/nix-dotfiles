{ inputs, pkgs, ... }:

{
  imports = [ inputs.mango.nixosModules.mango ];

  programs.mango = {
    enable = true;
    # Noctalia's user service has no logind scope. Import the greetd-provided
    # session ID in Mango's early C hook, before it starts the session target.
    # This same list is cleared on exit; no ID is captured at Nix evaluation.
    package = inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.mango.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/main.c \
          --replace-fail '"XDG_SESSION_TYPE",' '"XDG_SESSION_TYPE", "XDG_SESSION_ID",'
        grep -F '"XDG_SESSION_TYPE", "XDG_SESSION_ID",' src/main.c
      '';
    });
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
