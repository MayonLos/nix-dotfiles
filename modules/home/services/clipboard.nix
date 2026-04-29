{ pkgs, ... }:

let
  niriClipboard = pkgs.writeShellScriptBin "niri-clipboard" ''
    set -euo pipefail

    CLIPHIST="${pkgs.cliphist}/bin/cliphist"
    FUZZEL="${pkgs.fuzzel}/bin/fuzzel"
    WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    WL_PASTE="${pkgs.wl-clipboard}/bin/wl-paste"
    XCLIP="${pkgs.xclip}/bin/xclip"
    CLIPNOTIFY="${pkgs.clipnotify}/bin/clipnotify"
    FILE_BIN="${pkgs.file}/bin/file"
    SHA256SUM="${pkgs.coreutils}/bin/sha256sum"
    CUT="${pkgs.coreutils}/bin/cut"
    CAT="${pkgs.coreutils}/bin/cat"
    MKDIR="${pkgs.coreutils}/bin/mkdir"
    MKTEMP="${pkgs.coreutils}/bin/mktemp"
    RM="${pkgs.coreutils}/bin/rm"
    SLEEP="${pkgs.coreutils}/bin/sleep"
    PRINTF="${pkgs.coreutils}/bin/printf"

    STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}/niri-clipboard"
    HASH_STATE="$STATE_DIR/last-hash"

    ensure_state_dir() {
      "$MKDIR" -p "$STATE_DIR"
    }

    current_hash() {
      "$SHA256SUM" "$1" | "$CUT" -d " " -f 1
    }

    is_duplicate_hash() {
      local next_hash="$1"
      local prev_hash=""
      if [ -f "$HASH_STATE" ]; then
        prev_hash="$("$CAT" "$HASH_STATE" 2>/dev/null || true)"
      fi
      [ -n "$prev_hash" ] && [ "$prev_hash" = "$next_hash" ]
    }

    remember_hash() {
      "$PRINTF" "%s" "$1" >"$HASH_STATE"
    }

    sync_from_wayland() {
      local forced_mime="$1"
      local tmp mime hash

      ensure_state_dir
      tmp="$("$MKTEMP" -t niri-clip-wl.XXXXXX)"
      "$CAT" >"$tmp"

      if [ ! -s "$tmp" ]; then
        "$RM" -f "$tmp"
        return 0
      fi

      mime="$forced_mime"
      if [ -z "$mime" ]; then
        mime="$("$FILE_BIN" --brief --mime-type "$tmp" 2>/dev/null || true)"
      fi
      [ -n "$mime" ] || mime="text/plain"

      hash="$(current_hash "$tmp")"
      if is_duplicate_hash "$hash"; then
        "$RM" -f "$tmp"
        return 0
      fi

      if "$XCLIP" -selection clipboard -in -t "$mime" <"$tmp" 2>/dev/null; then
        remember_hash "$hash"
      fi

      "$RM" -f "$tmp"
    }

    sync_from_x11() {
      local tmp mime hash

      ensure_state_dir
      tmp="$("$MKTEMP" -t niri-clip-x11.XXXXXX)"
      mime=""

      if "$XCLIP" -selection clipboard -out -t image/png >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mime="image/png"
      elif "$XCLIP" -selection clipboard -out >"$tmp" 2>/dev/null; then
        if [ ! -s "$tmp" ]; then
          "$WL_COPY" --clear || true
          "$RM" -f "$tmp"
          return 0
        fi
        mime="$("$FILE_BIN" --brief --mime-type "$tmp" 2>/dev/null || true)"
        [ -n "$mime" ] || mime="text/plain"
      else
        "$RM" -f "$tmp"
        return 0
      fi

      hash="$(current_hash "$tmp")"
      if is_duplicate_hash "$hash"; then
        "$RM" -f "$tmp"
        return 0
      fi

      "$WL_COPY" --type "$mime" <"$tmp"
      remember_hash "$hash"
      "$RM" -f "$tmp"
    }

    menu() {
      local selection tmp mime hash

      ensure_state_dir
      selection="$("$CLIPHIST" list | "$FUZZEL" --dmenu || true)"
      [ -n "$selection" ] || return 0

      tmp="$("$MKTEMP" -t niri-clip-menu.XXXXXX)"
      if ! "$PRINTF" "%s\n" "$selection" | "$CLIPHIST" decode >"$tmp" 2>/dev/null; then
        "$RM" -f "$tmp"
        return 0
      fi

      if [ ! -s "$tmp" ]; then
        "$RM" -f "$tmp"
        return 0
      fi

      mime="$("$FILE_BIN" --brief --mime-type "$tmp" 2>/dev/null || true)"
      [ -n "$mime" ] || mime="text/plain"

      "$WL_COPY" --type "$mime" <"$tmp"
      hash="$(current_hash "$tmp")"
      remember_hash "$hash"
      "$RM" -f "$tmp"
    }

    clear_all() {
      ensure_state_dir
      "$CLIPHIST" wipe || true
      "$WL_COPY" --clear || true
      "$PRINTF" "" | "$XCLIP" -selection clipboard -in 2>/dev/null || true
      "$RM" -f "$HASH_STATE"
    }

    bridge() {
      local wl_text_pid wl_image_pid x11_pid

      ensure_state_dir
      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        exit 0
      fi

      "$WL_PASTE" --watch "$0" sync-from-wayland "text/plain" &
      wl_text_pid=$!

      "$WL_PASTE" --type image --watch "$0" sync-from-wayland "image/png" &
      wl_image_pid=$!

      (
        while true; do
          if ! "$CLIPNOTIFY" >/dev/null 2>&1; then
            "$SLEEP" 0.5
            continue
          fi
          "$0" sync-from-x11 || true
        done
      ) &
      x11_pid=$!

      trap 'kill "$wl_text_pid" "$wl_image_pid" "$x11_pid" 2>/dev/null || true' EXIT INT TERM
      wait "$wl_text_pid" "$wl_image_pid" "$x11_pid"
    }

    case "''${1:-}" in
      menu)
        menu
        ;;
      clear)
        clear_all
        ;;
      bridge)
        bridge
        ;;
      sync-from-wayland)
        sync_from_wayland "''${2:-}"
        ;;
      sync-from-x11)
        sync_from_x11
        ;;
      *)
        echo "Usage: niri-clipboard {menu|clear|bridge}" >&2
        exit 1
        ;;
    esac
  '';
in
{
  home.packages = [ niriClipboard ];

  systemd.user.services.niri-clipboard-bridge = {
    Unit = {
      Description = "Clipboard bridge between Wayland and X11 for niri";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${niriClipboard}/bin/niri-clipboard bridge";
      Restart = "on-failure";
      RestartSec = 1;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
