{ pkgs, ... }:
{
  services.flatpak.enable = true;

  systemd.services.flatpak-add-flathub = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      # Once the remote exists this is an offline-safe local no-op. The retry
      # loop only covers a fresh first-add racing WiFi/DNS that isn't up yet at
      # boot (oneshot can't use Restart=). Adding flathub is non-critical, so on
      # persistent failure we exit 0 rather than redden the boot — next boot
      # retries anyway.
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
