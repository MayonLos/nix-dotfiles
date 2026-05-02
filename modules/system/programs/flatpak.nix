{ pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-add-flathub = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };

  systemd.services.flatpak-global-overrides = {
    wantedBy = [ "multi-user.target" ];
    after = [ "flatpak-add-flathub.service" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak override --system \
        --env=GTK_IM_MODULE=fcitx5 \
        --env=QT_IM_MODULE=fcitx5 \
        --env=XMODIFIERS=@im=fcitx5 \
        --env=XCURSOR_THEME=Bibata-Modern-Ice \
        --env=XCURSOR_SIZE=16 \
        --filesystem=/nix/store:ro
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };
}
