{ pkgs, ... }:
let
  tools = import ../tools.nix { inherit pkgs; };
in
{
  programs.steam = {
    enable = true;
    extraCompatPackages = [ pkgs.proton-ge-bin ];
    package = pkgs.steam.override {
      # Both ABIs of libgamemode are supplied so `gamemoderun %command%` works
      # for native and Proton games.
      extraLibraries = p: [ p.gamemode.lib ];
      # No session-wide LD_PRELOAD of libgamemodeauto: every Steam helper then
      # registers with gamemoded. steam-runtime lsof closes the library's
      # cached D-Bus socket before its destructor, exposing the old client's
      # NULL-pending-call assertion and breaking the websocket check (0x3008).
      # Even with that library bug fixed, helpers shouldn't request GameMode.
      extraProfile = ''
        eval "$(${tools.game-run}/bin/game-run --env)"
      '';
    };

    # No STEAM_FORCE_DESKTOPUI_SCALING override here, deliberately.
    #
    # Steam is an X11 client and gets its size from `Xft.dpi: 144`
    # (base/xresources.nix), same as every other X client on this host. Pinning
    # Steam's own scaling to 1 was tried on 2026-09-18 and fixed the size while
    # leaving the text soft -- because the softness was never Steam's doing:
    # Xwayland was running at 1707x1067 and being stretched to the panel.
    # `xwayland_ignore_scale = 1` in wm/mango/config.nix is the actual fix, and
    # with it Steam at 144 DPI is both the right size and sharp.

    # Both of these open inbound ports, so only the ones actually used are on.
    # `dedicatedServer.openFirewall` is deliberately absent: it opens TCP+UDP
    # 27015 for an SRCDS server this host does not run, on a laptop that joins
    # public networks (see core/network.nix).
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;

    gamescopeSession.enable = true;
    extraPackages = [
      pkgs.mangohud
      tools.game-run
      tools.gamescope-run
    ];
  };
}
