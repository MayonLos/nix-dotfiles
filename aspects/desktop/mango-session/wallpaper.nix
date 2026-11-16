{ palette }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkGraphicalService = import ../../../lib/service.nix;
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs palette;
  };
  wallpaperRoot = "${config.home.homeDirectory}/Pictures/Wallpapers";
  factoryDefault = "${wallpapers.default}";
  sweetbg = pkgs.local.sweetbg;
  # managed/ is a Home Manager link farm whose top-level entry is a symlink;
  # the picker must follow it or the grid is empty. The patch is private to
  # this feature.
  matuwall = pkgs.local.matuwall.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./resources/matuwall-follow-symlink-dirs.patch ];
  });
  # One apply path for the keybind/picker and for session restore. It keeps
  # the last choice in the user state file, but the renderer is the sweetbgd
  # daemon: applying a wallpaper is an IPC command, not a process restart.
  # Only regular files (or symlinks to them) directly under managed/ or
  # local/ are accepted; anything else is ignored.
  wallpaperApply = pkgs.writeShellApplication {
    name = "wallpaper-apply";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      root=$HOME/Pictures/Wallpapers
      state_dir=$HOME/.local/state/mango-session
      state=$state_dir/wallpaper
      factory=${factoryDefault}
      sweetbg=${sweetbg}/bin/sweetbg

      valid() {
        local path=$1 rel base ext
        case "$path" in
          "$root"/managed/* | "$root"/local/*) ;;
          *) return 1 ;;
        esac
        rel=''${path#"$root"/}
        base=''${rel#*/}
        if [[ $base == */* || $base == . || $base == .. || $base == "$rel" ]]; then
          return 1
        fi
        ext=''${base##*.}
        ext=''${ext,,}
        case "$ext" in
          jpg | jpeg | png | webp) ;;
          *) return 1 ;;
        esac
        [[ -f $path ]]
      }

      wait_for_daemon() {
        local _
        for _ in $(seq 1 50); do
          if "$sweetbg" query >/dev/null 2>&1; then
            return 0
          fi
          sleep 0.1
        done
        return 1
      }

      # Matuwall resolves symlinks for the backend, so managed/ images arrive
      # as their /nix/store target. Map such a target back to the managed or
      # local entry that owns it; accept a direct entry path as before.
      resolve() {
        local candidate=$1 entry resolved side
        if valid "$candidate"; then
          image=$candidate
          return 0
        fi
        [[ -f $candidate ]] || return 1
        for side in managed local; do
          for entry in "$root/$side"/*; do
            resolved=$(readlink -f -- "$entry" 2>/dev/null) || continue
            if [[ $resolved == "$candidate" ]]; then
              image=$entry
              return 0
            fi
          done
        done
        return 1
      }

      case ''${1:-} in
        --restore)
          image=$factory
          if [[ -f $state ]]; then
            candidate=""
            IFS= read -r candidate <"$state" || true
            if valid "$candidate"; then
              image=$candidate
            fi
          fi
          ;;
        *)
          if [ "$#" -ne 1 ] || ! resolve "$1"; then
            echo "usage: wallpaper-apply <managed|local image>" >&2
            exit 2
          fi
          ;;
      esac

      wait_for_daemon || {
        echo "wallpaper-apply: sweetbgd is not ready" >&2
        exit 1
      }
      "$sweetbg" img "$image"

      case ''${1:-} in
        --restore) ;;
        *)
          mkdir -p -- "$state_dir"
          tmp=$(mktemp "$state_dir/wallpaper.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          printf '%s\n' "$image" >"$tmp"
          mv -f -- "$tmp" "$state"
          trap - EXIT
          ;;
      esac
    '';
  };
  # Super+W. Matuwall scans the same two directories and calls the one apply
  # path above through its command backend. The local Matuwall patch follows
  # symlinked directories, because managed/ is a Home Manager link farm.
  wallpaperPick = pkgs.writeShellApplication {
    name = "wallpaper-pick";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      exec ${lib.getExe matuwall} --no-config \
        --directory "$HOME/Pictures/Wallpapers" --recursive \
        --backend-command "${lib.getExe wallpaperApply} {path}" \
        --columns 4 --width 320 --height 180 \
        --background "${palette.bg}e6" \
        --tile "${palette.surface}" \
        --border "${palette.border}" \
        --ring "${palette.blue}" \
        --spinner "${palette.brightFg}" \
        --radius 10 --panel-radius 16 \
        --preview \
        "$@"
    '';
  };
in
{
  # The managed wallpaper set ships in the store as a directory of links. HM
  # owns only this one link; user pictures stay outside the store and Git.
  home = {
    packages = [
      wallpaperApply
      wallpaperPick
    ];
    file."Pictures/Wallpapers/managed".source = wallpapers.directory;

    activation.wallpaperLocalDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      local_wallpapers=${lib.escapeShellArg "${wallpaperRoot}/local"}
      if [ -e "$local_wallpapers" ] || [ -L "$local_wallpapers" ]; then
        if [ ! -d "$local_wallpapers" ]; then
          echo "Wallpapers/local exists and is not a directory; preserving it" >&2
          exit 1
        fi
      else
        run mkdir -p -- "$local_wallpapers"
      fi
    '';
  };

  # Renderer config is declarative and read-only: the daemon starts on the
  # factory image and `wallpaper-apply --restore` then applies the saved
  # choice. sweetbg never writes this file because it is not invoked with
  # --persist; the state file and the picker remain the only writers.
  xdg.configFile."sweetbg/config.toml".text = ''
    image = "${factoryDefault}"
    color = "${palette.bg}"
    fit = "cover"
  '';

  # Mango itself paints only `root_color`. One sweetbgd process on the session
  # target owns the layer surface; ExecStartPost restores the last choice after
  # each daemon start. The greeter and the lock screen do not read the state
  # file and keep their own factory-default image.
  systemd.user.services.sweetbgd = mkGraphicalService {
    target = "mango-session.target";
    description = "Wayland wallpaper daemon (sweetbg)";
    unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    service = {
      ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
      ExecStart = "${sweetbg}/bin/sweetbgd";
      ExecStartPost = "-${lib.getExe wallpaperApply} --restore";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
