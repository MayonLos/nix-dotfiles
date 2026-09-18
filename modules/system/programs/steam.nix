{ pkgs, ... }:

{
  programs.steam = {
    enable = true;

    # Steam's client is an X11 application, so it runs through mango's built-in
    # Xwayland, whose screen is in *physical* pixels (X11 = logical x scale).
    # base/xresources.nix merges `Xft.dpi: 144` into that server for fcitx5's
    # candidate window, and Steam's desktop UI reads Xft.dpi too -- which is why
    # the whole client grew by exactly the 1.5 output scale the moment that
    # merge landed (974ad9c, written for QQ).
    #
    # Pin Steam's own scaling instead of unsetting the resource, which every
    # other X client here still needs. "1" reproduces the pre-974ad9c size; set
    # it to 1.25 or 1.5 if the client is now too small on this panel.
    package = pkgs.steam.override {
      extraEnv.STEAM_FORCE_DESKTOPUI_SCALING = "1";
    };

    # Both of these open inbound ports, so only the ones actually used are on.
    # `dedicatedServer.openFirewall` is deliberately absent: it opens TCP+UDP
    # 27015 for an SRCDS server this host does not run, on a laptop that joins
    # public networks (see core/network.nix).
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;

    gamescopeSession.enable = true;
    extraPackages = [ pkgs.mangohud ];
  };
}
