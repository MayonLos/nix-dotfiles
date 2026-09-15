{ pkgs, ... }:

let
  # Selection sync between Xwayland and Wayland does not happen on this host,
  # so without this bridge the two clipboards are separate. This module was
  # written for xwayland-satellite under niri, dropped in the mango migration
  # on the assumption that wlroots' built-in Xwayland syncs selections inside
  # the compositor, and restored when that assumption was finally measured.
  #
  # Measured 2026-09-15 on running mango, both directions dead:
  #
  #   X11 -> Wayland  QQ copied text landed in the X11 CLIPBOARD (xclip -o
  #                   returned it) while wl-paste still served a minutes-old
  #                   PNG and cliphist recorded nothing.
  #   Wayland -> X11  wl-copy of a marker string, then
  #                   `xclip -selection clipboard -o` -> "target STRING not
  #                   available".
  #
  # Nothing is missing on the compositor side: mango advertises
  # wl_data_device_manager v3, zwp_primary_selection_device_manager_v1,
  # zwlr_data_control_manager_v1 v2 and ext_data_control_manager_v1.
  #
  # What makes this matter beyond legacy X11 apps is QQ. It is a mixed-protocol
  # client -- Wayland for its windows (zero connections to @/tmp/.X11-unix/X0
  # while idle, input over text-input-v3) but X11 for the clipboard, which it
  # reaches through DISPLAY=:0 only when copying. So "copy in QQ does nothing"
  # is this bug, not a QQ-side one, and re-pinning QQ to --ozone-platform=x11
  # to work around it would wreck the fcitx5 setup described in desktop-mango.
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

      # Every read below is time-boxed, and that is load-bearing rather than
      # defensive. wl-paste blocks forever if the selection owner dies during
      # the transfer, which is routine here: mark-shot holds a screenshot with
      # `wl-copy --foreground` and that holder is killed the moment its window
      # closes, mid-read. A hung reader would be survivable if it only lost one
      # sync -- but `wl-paste --watch` runs its command *serially*, so one stuck
      # child wedges the watcher permanently and every later copy silently stops
      # reaching X11 until the session restarts. Observed 2026-09-07: a
      # from-wayland child sat on `wl-paste --type image/png` for seven minutes
      # while the X11 side stayed frozen on a seven-minute-old payload, which is
      # the "screenshot sometimes does not reach the clipboard" report.
      READ_TIMEOUT=5

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
        types="$(timeout "$READ_TIMEOUT" wl-paste --list-types 2>/dev/null)" || return 0
        mime="$(pick_type "$types")" || return 0

        tmp="$(mktemp -t cb-wl.XXXXXX)"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp'" RETURN

        timeout "$READ_TIMEOUT" wl-paste --no-newline --type "$mime" >"$tmp" 2>/dev/null || return 0
        [ -s "$tmp" ] || return 0

        hash="$(sha256sum "$tmp" | cut -d' ' -f1)"
        is_duplicate "$hash" && return 0

        # X11 wants the concrete type name, not the charset-qualified one.
        case "$mime" in
          "text/plain;charset=utf-8" | text/plain) mime=UTF8_STRING ;;
          *) ;;
        esac

        # Recorded before the handover, not after: xclip taking ownership wakes
        # clipnotify, and the from-x11 side must already see this hash or it
        # reflects the payload straight back.
        printf '%s' "$hash" >"$HASH_STATE"
        xclip -selection clipboard -t "$mime" -i <"$tmp" || return 0
      }

      sync_from_x11() {
        local types mime tmp hash
        types="$(timeout "$READ_TIMEOUT" xclip -selection clipboard -t TARGETS -o 2>/dev/null)" || return 0
        mime="$(pick_type "$types")" || return 0

        tmp="$(mktemp -t cb-x11.XXXXXX)"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp'" RETURN

        timeout "$READ_TIMEOUT" xclip -selection clipboard -t "$mime" -o >"$tmp" 2>/dev/null || return 0
        [ -s "$tmp" ] || return 0

        hash="$(sha256sum "$tmp" | cut -d' ' -f1)"
        is_duplicate "$hash" && return 0

        case "$mime" in
          UTF8_STRING | STRING) mime="text/plain;charset=utf-8" ;;
          *) ;;
        esac

        printf '%s' "$hash" >"$HASH_STATE"
        wl-copy --type "$mime" <"$tmp"
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
      Description = "Clipboard bridge between Wayland and X11 (the compositor does not sync selections)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # DISPLAY is exported into the user bus by the dbus-update-activation-environment
      # line in mango's autostart.sh (see desktop-mango on why autostart_sh
      # is what runs it); without it the X11 half silently no-ops. Verify
      # with `systemctl --user show-environment`.
      ExecStart = "${clipboardBridge}/bin/clipboard-bridge bridge";
      # `wait` in bridge() returns as soon as the first watcher exits, so the
      # service can end with status 0 while the clipboard is no longer bridged.
      # on-failure would leave that dead; always brings it back.
      Restart = "always";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
