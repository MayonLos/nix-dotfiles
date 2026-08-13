{ pkgs, ... }:

let
  # xwayland-satellite's clipboard is completely dead on this host: it claims
  # the X11 CLIPBOARD selection and advertises the right targets, then serves
  # zero bytes for every one of them, and the X11 -> Wayland direction never
  # fires at all. Verified 2026-08-13 against both 0.8.1 (stable) and 0.8.2
  # (unstable), with an X11 window focused so the seat's wl_data_device was
  # actually reachable. niri 26.04 advertises everything satellite binds
  # (ext_data_control_manager_v1 v1, wl_data_device_manager v3,
  # zwp_primary_selection_device_manager_v1), so nothing is missing on the
  # compositor side — this is an upstream bug. Delete this module once it is
  # fixed and satellite starts moving bytes.
  #
  # Compared to the previous version of this bridge, the mime type is taken
  # from the *offered type list* on each side instead of being guessed by
  # sniffing the bytes with `file`. That is what makes images survive: sniffing
  # a Thunar copy only ever saw a path string, so image/png never crossed.
  clipboardBridge = pkgs.writeShellApplication {
    name = "clipboard-bridge";
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      clipnotify
      coreutils
    ];
    text = ''
      STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/clipboard-bridge"
      HASH_STATE="$STATE_DIR/last-hash"

      # Both directions share one hash file on purpose: it is what stops the
      # two watchers from bouncing the same payload back and forth forever.
      is_duplicate() {
        [ -f "$HASH_STATE" ] || return 1
        [ "$(cat "$HASH_STATE")" = "$1" ]
      }

      # Pick the richest type both sides can actually use. Images first —
      # falling through to text/plain is exactly how a copied image degrades
      # into a bare path. TARGETS/MULTIPLE/TIMESTAMP are X11 metadata, and
      # x-special/* / text/uri-list are file references that mean nothing to
      # the other side's paste handler.
      pick_type() {
        local types="$1"
        local candidate
        for candidate in image/png image/jpeg image/gif image/bmp; do
          if printf '%s\n' "$types" | grep -qxF "$candidate"; then
            printf '%s' "$candidate"
            return 0
          fi
        done
        for candidate in "text/plain;charset=utf-8" text/plain UTF8_STRING STRING; do
          if printf '%s\n' "$types" | grep -qxF "$candidate"; then
            printf '%s' "$candidate"
            return 0
          fi
        done
        return 1
      }

      sync_from_wayland() {
        local types mime tmp hash
        types="$(wl-paste --list-types 2>/dev/null)" || return 0
        mime="$(pick_type "$types")" || return 0

        tmp="$(mktemp -t cb-wl.XXXXXX)"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp'" RETURN

        wl-paste --no-newline --type "$mime" >"$tmp" 2>/dev/null || return 0
        [ -s "$tmp" ] || return 0

        hash="$(sha256sum "$tmp" | cut -d' ' -f1)"
        is_duplicate "$hash" && return 0

        # X11 wants the concrete type name, not the charset-qualified one.
        case "$mime" in
          "text/plain;charset=utf-8" | text/plain) mime=UTF8_STRING ;;
          *) ;;
        esac

        xclip -selection clipboard -t "$mime" -i <"$tmp" || return 0
        printf '%s' "$hash" >"$HASH_STATE"
      }

      sync_from_x11() {
        local types mime tmp hash
        types="$(xclip -selection clipboard -t TARGETS -o 2>/dev/null)" || return 0
        mime="$(pick_type "$types")" || return 0

        tmp="$(mktemp -t cb-x11.XXXXXX)"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp'" RETURN

        xclip -selection clipboard -t "$mime" -o >"$tmp" 2>/dev/null || return 0
        [ -s "$tmp" ] || return 0

        hash="$(sha256sum "$tmp" | cut -d' ' -f1)"
        is_duplicate "$hash" && return 0

        case "$mime" in
          UTF8_STRING | STRING) mime="text/plain;charset=utf-8" ;;
          *) ;;
        esac

        wl-copy --type "$mime" <"$tmp"
        printf '%s' "$hash" >"$HASH_STATE"
      }

      bridge() {
        [ -n "''${WAYLAND_DISPLAY:-}" ] || exit 0
        mkdir -p "$STATE_DIR"

        wl-paste --watch "$0" from-wayland &
        local wl_pid=$!

        (
          while true; do
            clipnotify >/dev/null 2>&1 || sleep 0.5
            "$0" from-x11 || true
          done
        ) &
        local x11_pid=$!

        # shellcheck disable=SC2064
        trap "kill $wl_pid $x11_pid 2>/dev/null || true" EXIT INT TERM
        wait "$wl_pid" "$x11_pid"
      }

      case "''${1:-}" in
        bridge) bridge ;;
        from-wayland) mkdir -p "$STATE_DIR" && sync_from_wayland ;;
        from-x11) mkdir -p "$STATE_DIR" && sync_from_x11 ;;
        *)
          echo "usage: clipboard-bridge {bridge|from-wayland|from-x11}" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  home.packages = [ clipboardBridge ];

  systemd.user.services.clipboard-bridge = {
    Unit = {
      Description = "Clipboard bridge between Wayland and X11 (xwayland-satellite's is broken)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # DISPLAY is exported into the user bus by the dbus-update-activation-environment
      # call in niri's config; without it the X11 half silently no-ops.
      ExecStart = "${clipboardBridge}/bin/clipboard-bridge bridge";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
