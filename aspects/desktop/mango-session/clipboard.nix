{
  config,
  lib,
  pkgs,
  ...
}:

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
  };

  mkGraphicalService = import ../../../lib/service.nix;
  cliphistTui = import ./cliphist-tui.nix { inherit pkgs; };
  # Sends evdev KEY_V (47). wtype `-k v` sends keycode 1, which this Mango
  # reads as Escape and opens the btop scratchpad on Ctrl+Shift.
  pasteKey = pkgs.stdenv.mkDerivation {
    pname = "paste-key";
    version = "0.1.0";
    src = ./resources;
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.wayland-scanner
    ];
    buildInputs = [ pkgs.wayland ];
    buildPhase = ''
      # wayland-protocols 1.49 no longer ships this XML. The copy in resources
      # is virtual-keyboard-unstable-v1, the interface Mango's wlroots implements.
      wayland-scanner client-header virtual-keyboard-unstable-v1.xml virtual-keyboard-unstable-v1-client-protocol.h
      wayland-scanner private-code virtual-keyboard-unstable-v1.xml virtual-keyboard-unstable-v1-protocol.c
      $CC -O2 -o paste-key paste-key.c virtual-keyboard-unstable-v1-protocol.c \
        $(pkg-config --cflags --libs wayland-client)
    '';
    installPhase = ''
      install -Dm755 paste-key $out/bin/paste-key
    '';
  };
  # Super+V. cliphist still owns the database. cliphist-tui draws the list in
  # a floating Kitty window and previews images with the Kitty graphics
  # protocol. Enter copies the entry back through wl-copy and writes
  # CT_COPY_MARK; Escape leaves the mark empty. The focused appid is read
  # before Kitty takes the seat. After the window closes, paste-key sends
  # KEY_V with Ctrl, plus Shift in a terminal. Image rows are not typed into
  # terminals. The TUI's own wl-paste --watch only reloads the open list; it
  # does not call `cliphist store`. Alt+X inside the TUI wipes the database.
  clipboardHistory = pkgs.writeShellApplication {
    name = "clipboard-history";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.kitty
      cliphistTui
      pkgs.wl-clipboard
      pasteKey
    ];
    text = ''
      set -euo pipefail

      mmsg=${config.wayland.windowManager.mango.package}/bin/mmsg
      appid=""
      socket="''${MANGO_INSTANCE_SIGNATURE:-}"
      if [ -z "$socket" ]; then
        for candidate in /run/user/"$(id -u)"/mango-*.sock; do
          if [ -S "$candidate" ]; then
            socket=$candidate
            break
          fi
        done
      fi
      if [ -n "$socket" ] && [ -S "$socket" ]; then
        client=$(MANGO_INSTANCE_SIGNATURE="$socket" "$mmsg" get focusing-client 2>/dev/null || true)
        appid=$(printf '%s' "$client" | jq -r 'if type == "object" then (.appid // empty) else empty end' 2>/dev/null || true)
      fi

      mark=$(mktemp)
      trap 'rm -f "$mark"' EXIT

      CT_COPY_MARK=$mark kitty --class=cliphist-tui --title "剪贴板" cliphist-tui || true
      if [ ! -s "$mark" ]; then
        exit 0
      fi

      # Kitty has released the seat. A short pause lets the previous client
      # take focus before the synthetic paste. A terminal image paste would
      # dump bytes into the shell, so images there stay on the clipboard.
      sleep 0.08
      types=$(timeout 2 wl-paste --list-types 2>/dev/null || true)
      is_image=0
      if printf '%s\n' "$types" | grep -q '^image/'; then
        is_image=1
      fi
      case "$appid" in
        kitty | Alacritty | foot | wezterm | org.wezfurlong.wezterm | com.mitchellh.ghostty | org.gnome.Terminal | xterm)
          if [ "$is_image" -eq 1 ]; then
            exit 0
          fi
          paste-key ctrl shift v || true
          ;;
        *)
          paste-key ctrl v || true
          ;;
      esac
    '';
  };
  sessionService = {
    Unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      # force: cliphist and wl-clip-persist restart only on failure; a clean exit still drops history.
      Restart = lib.mkForce "always";
      RestartSec = 2;
    };
  };
in
{
  home.packages = [
    clipboardBridge
    clipboardHistory
  ];

  services = {
    cliphist = {
      enable = true;
      allowImages = true;
      systemdTargets = [ "mango-session.target" ];
    };

    wl-clip-persist = {
      enable = true;
      clipboardType = "regular";
      extraOptions = [
        "--reconnect-tries"
        "0"
      ];
      systemdTargets = [ "mango-session.target" ];
    };
  };

  systemd.user.services = {
    cliphist = sessionService;
    cliphist-images = sessionService;
    wl-clip-persist = sessionService;

    clipboard-bridge = mkGraphicalService {
      target = "mango-session.target";
      unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      description = "Clipboard bridge between Wayland and X11 (the compositor does not sync selections)";
      service = {
        Type = "simple";
        # Mango's C startup imports dynamic DISPLAY/WAYLAND environment before
        # requesting its session target; HM autostart supplies an additional sync.
        # Verify actual manager values on cold login, rather than assuming ordering.
        ExecStart = "${clipboardBridge}/bin/clipboard-bridge bridge";
        # `wait` in bridge() returns as soon as the first watcher exits, so the
        # service can end with status 0 while the clipboard is no longer bridged.
        # on-failure would leave that dead; always brings it back.
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
