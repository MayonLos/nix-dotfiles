# X11 <-> Wayland clipboard bridge, shared by all three sessions.
#
# Kept verbatim from the old Mango session module: the measured failure on
# 2026-09-15 was a compositor-independent XWayland selection problem (QQ copies
# over X11 and nothing reaches Wayland), so the bridge is part of the session
# contract, not of a particular desktop shell.
{ pkgs }:
pkgs.writeShellApplication {
  name = "clipboard-bridge";
  runtimeInputs = with pkgs; [
    wl-clipboard
    xclip
    clipnotify
    coreutils
    gnugrep
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
      # --watch has already requested a transfer and passes its pipe on stdin.
      # Drain it before asking the owner for anything else: wl-copy serves
      # requests serially, so an unread image larger than the pipe buffer
      # blocks the owner and our second wl-paste times out after five seconds.
      # Read again below with an explicit offered MIME: watch's automatic
      # choice can be text/uri-list even when image/png is also available.
      timeout "$READ_TIMEOUT" cat >/dev/null || return 0

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

      local stopping=0
      local wl_pid=""
      local x11_pid=""

      # ShellCheck does not resolve these nested functions through trap.
      # shellcheck disable=SC2329
      request_stop() {
        stopping=1
        [ -z "$wl_pid" ] || kill "$wl_pid" 2>/dev/null || true
        [ -z "$x11_pid" ] || kill "$x11_pid" 2>/dev/null || true
      }

      # shellcheck disable=SC2329
      cleanup_watchers() {
        [ -z "$wl_pid" ] || kill "$wl_pid" 2>/dev/null || true
        [ -z "$x11_pid" ] || kill "$x11_pid" 2>/dev/null || true
      }

      trap request_stop INT TERM
      trap cleanup_watchers EXIT

      wl-paste --watch "$0" from-wayland &
      wl_pid=$!

      (
        while true; do
          clipnotify >/dev/null 2>&1 || sleep 0.5
          "$0" from-x11 || true
        done
      ) &
      x11_pid=$!

      # systemd stops this unit with TERM while Mango is tearing down its
      # displays. Treat that requested shutdown as clean, while an
      # independently exiting watcher still fails and triggers Restart.
      # Wait for the first watcher to exit; waiting on both PIDs here would
      # leave the bridge alive with one direction broken.
      # Exit inside bridge so EXIT cleanup still sees its local watcher PIDs
      # under writeShellApplication's nounset mode.
      wait -n "$wl_pid" "$x11_pid" || true
      if [ "$stopping" -eq 1 ]; then
        exit 0
      fi
      # The compositor may lose its display before this unit receives TERM
      # during system shutdown. Only that explicit manager state is clean;
      # a watcher failure while the machine is running must still restart.
      if [ "$(timeout 1s ${pkgs.systemd}/bin/systemctl is-system-running 2>/dev/null || true)" = stopping ]; then
        exit 0
      fi
      exit 1
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
}
