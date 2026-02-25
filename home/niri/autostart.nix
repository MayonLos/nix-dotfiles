{ pkgs, ... }:
let
  clipboardBridge = pkgs.writeShellScriptBin "niri-clipboard-bridge" ''
    set -eu

    tmp_wl="$(mktemp -t niri-wl-clip.XXXXXX)"
    tmp_x="$(mktemp -t niri-x-clip.XXXXXX)"
    trap 'rm -f "$tmp_wl" "$tmp_x"' EXIT

    last_wl=""
    last_x=""

    while true; do
      wl-paste --no-newline >"$tmp_wl" 2>/dev/null || : >"$tmp_wl"
      xclip -selection clipboard -out >"$tmp_x" 2>/dev/null || : >"$tmp_x"

      wl_hash="$(${pkgs.coreutils}/bin/sha256sum "$tmp_wl" | ${pkgs.coreutils}/bin/cut -d " " -f 1)"
      x_hash="$(${pkgs.coreutils}/bin/sha256sum "$tmp_x" | ${pkgs.coreutils}/bin/cut -d " " -f 1)"

      if [ "$x_hash" != "$last_x" ] && [ "$x_hash" != "$wl_hash" ]; then
        wl-copy <"$tmp_x"
        last_x="$x_hash"
        last_wl="$x_hash"
      elif [ "$wl_hash" != "$last_wl" ] && [ "$wl_hash" != "$x_hash" ]; then
        xclip -selection clipboard -in <"$tmp_wl"
        last_wl="$wl_hash"
        last_x="$wl_hash"
      fi

      sleep 0.25
    done
  '';
in
{
  programs.niri.settings = {
    xwayland-satellite = {
      enable = true;
      path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
    };
    spawn-at-startup = [
      {
        command = [
          "dbus-update-activation-environment"
          "--systemd"
          "WAYLAND_DISPLAY"
          "XDG_CURRENT_DESKTOP"
          "XDG_SESSION_TYPE"
          "DISPLAY"
        ];
      }

      { command = [ "${pkgs.swww}/bin/swww-daemon" ]; }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.3 && ${pkgs.swww}/bin/swww-daemon -n overview"
        ];
      }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.8 && ${pkgs.swww}/bin/swww img ${../wallpaper/wallpaper.jpg}"
        ];
      }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.8 && ${pkgs.swww}/bin/swww img ${../wallpaper/overview.jpg} -n overview"
        ];
      }

      { command = [ "${clipboardBridge}/bin/niri-clipboard-bridge" ]; }

      { command = [ "waybar" ]; }
    ];
  };
}
