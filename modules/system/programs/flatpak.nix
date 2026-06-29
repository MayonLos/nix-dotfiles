{ pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-add-flathub = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      for attempt in $(seq 1 12); do
        if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
          exit 0
        fi
        echo "flathub not reachable yet (attempt $attempt/12), retrying in 10s..." >&2
        sleep 10
      done
      echo "could not add flathub after retries; will retry next boot" >&2
      exit 0
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };

  systemd.services.flatpak-global-overrides = {
    wantedBy = [ "multi-user.target" ];
    after = [ "flatpak-add-flathub.service" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak override --system --reset
      flatpak override --system \
        --socket=wayland \
        --filesystem=/nix/store:ro \
        --filesystem=xdg-data/icons:ro \
        --filesystem=xdg-data/themes:ro \
        --filesystem=home \
        --env=GDK_BACKEND=wayland \
        --env=ELECTRON_OZONE_PLATFORM_HINT=wayland \
        --env=QT_QPA_PLATFORM=wayland \
        --env=XMODIFIERS=@im=fcitx \
        --env=XCURSOR_THEME=Bibata-Modern-Ice \
        --env=XCURSOR_SIZE=24
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };
}
