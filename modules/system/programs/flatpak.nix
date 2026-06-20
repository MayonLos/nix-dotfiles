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
      # Fully declarative: wipe any accumulated manual overrides first, then
      # write exactly what we want. This avoids stale state in
      # /var/lib/flatpak/overrides/global (e.g. a manually-set PATH that drops
      # /app/bin and makes apps fail with "bwrap: execvp <cmd>: No such file").
      # NEVER set PATH here — the sandbox default already includes /app/bin.
      flatpak override --system --reset

      # GTK_IM_MODULE/QT_IM_MODULE are intentionally left unset so Wayland apps
      # use the text-input-v3 protocol → fcitx5 wayland frontend, whose candidate
      # window follows the niri output scale (1.5). Forcing the legacy fcitx5 IM
      # module routes through XWayland at 96 DPI (scale 1), shrinking the popup.
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
