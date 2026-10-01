{ pkgs, lib, ... }:

let
  # Thunar's Ctrl+C only ever offers file references (text/uri-list +
  # x-special/gnome-copied-files + the path as plain text) — it never puts image
  # pixel data on the clipboard. That is GTK file-manager design, not a bug, and
  # it is why pasting into WeChat/Zen/Typora yields a bare path while
  # paste-inside-Thunar works fine.
  #
  # This script supplies the missing step: the image data itself.
  copyImage = pkgs.writeShellApplication {
    name = "copy-image";
    runtimeInputs = with pkgs; [
      imagemagick
      wl-clipboard
      xclip
      libnotify
      file
      coreutils
    ];
    text = ''
      fail() {
        notify-send --app-name=copy-image --icon=dialog-error "Copy as image failed" "$1"
        exit 1
      }

      [ $# -ge 1 ] || fail "No file selected"

      src="$1"
      [ -f "$src" ] || fail "Not a regular file: $src"

      mime="$(file --brief --mime-type "$src")"
      case "$mime" in
        image/*) ;;
        *) fail "Not an image: $mime ($src)" ;;
      esac

      # Normalise to PNG. WeChat, Zen and Typora all accept image/png, whereas
      # image/webp, image/heic and image/avif are widely rejected; JPEG usually
      # works but converting unconditionally keeps this branch-free.
      # "[0]" takes the first frame so animations and multi-page TIFFs don't
      # make magick emit a whole pile of files.
      tmp=""
      if [ "$mime" = "image/png" ]; then
        png="$src"
      else
        tmp="$(mktemp -t copy-image.XXXXXX.png)"
        magick "''${src}[0]" png:"$tmp" || fail "PNG conversion failed: $src"
        png="$tmp"
      fi

      # Both clipboards get written:
      #   wl-copy -> native Wayland clients (QQ, Zen and Typora)
      #   xclip   -> XWayland clients (wechat-uos pins QT_QPA_PLATFORM=xcb)
      # Mango does *not* synchronise the two selections (measured 2026-09-15,
      # see the desktop-mango skill) -- services/clipboard.nix bridges them on a
      # timer. Writing both sides directly here makes this action independent of
      # that bridge, of selection ownership, and of focus timing.
      #
      # Both commands slurp stdin into memory before forking off to serve the
      # selection, so the temp file can go away immediately afterwards.
      wl-copy --type image/png <"$png"
      xclip -selection clipboard -t image/png -i <"$png"

      [ -z "$tmp" ] || rm -f "$tmp"

      notify-send --app-name=copy-image --icon=edit-copy \
        "Copied as image" "$(basename "$src")"
    '';
  };

  # Thunar builds custom-action accel paths as "uca-action-<unique-id>" under
  # <Actions>/ThunarActions/ (confirmed against the thunar-uca plugin binary).
  copyImageId = "copy-image-as-png-1";
  copyImageAccel = ''(gtk_accel_path "<Actions>/ThunarActions/uca-action-${copyImageId}" "<Primary><Shift>c")'';

  # Paths are text, but WeChat still reads the X11 selection. Write both,
  # same reason as copy-image.
  copyPath = pkgs.writeShellApplication {
    name = "copy-path";
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      libnotify
      coreutils
    ];
    text = ''
      [ "$#" -ge 1 ] || exit 1
      payload="$(printf '%s\n' "$@")"
      printf '%s' "$payload" | wl-copy --type text/plain
      printf '%s' "$payload" | xclip -selection clipboard -t text/plain -i
      if [ "$#" -eq 1 ]; then
        notify-send --app-name=copy-path --icon=edit-copy "Copied path" "$1"
      else
        notify-send --app-name=copy-path --icon=edit-copy "Copied paths" "$# selected"
      fi
    '';
  };

  pasteClipboardImage = pkgs.writeShellApplication {
    name = "paste-clipboard-image";
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      imagemagick
      libnotify
      coreutils
      gnugrep
    ];
    text = ''
      fail() {
        notify-send --app-name=paste-clipboard-image --icon=dialog-error "Paste image failed" "$1"
        exit 1
      }

      [ "$#" -ge 1 ] || fail "No destination"
      dest="$1"
      if [ ! -d "$dest" ]; then
        dest="$(dirname "$dest")"
      fi
      [ -d "$dest" ] || fail "Not a directory: $dest"

      types="$(wl-paste --list-types 2>/dev/null || true)"
      if printf '%s\n' "$types" | grep -qx 'image/png'; then
        mime="image/png"
        source="wayland"
      else
        mime="$(printf '%s\n' "$types" | grep '^image/' | head -n 1 || true)"
        source="wayland"
      fi
      if [ -z "$mime" ]; then
        types="$(xclip -selection clipboard -t TARGETS -o 2>/dev/null || true)"
        if printf '%s\n' "$types" | grep -qx 'image/png'; then
          mime="image/png"
        else
          mime="$(printf '%s\n' "$types" | grep '^image/' | head -n 1 || true)"
        fi
        source="x11"
      fi
      [ -n "$mime" ] || fail "Clipboard has no image"

      base="img_$(date -Iseconds | cut -d+ -f1 | tr 'T:' '_-')"
      out="$dest/$base.png"
      n=1
      while [ -e "$out" ]; do
        out="$dest/''${base}_$n.png"
        n=$((n + 1))
      done
      part="$(mktemp -t paste-clipboard-image.XXXXXX)"
      if [ "$source" = "wayland" ]; then
        wl-paste --type "$mime" >"$part" || fail "Could not read the Wayland clipboard"
      else
        xclip -selection clipboard -t "$mime" -o >"$part" || fail "Could not read the X11 clipboard"
      fi
      if [ "$mime" = "image/png" ]; then
        mv "$part" "$out"
      else
        magick "''${part}[0]" "png:$out" || fail "PNG conversion failed"
        rm -f "$part"
      fi
      notify-send --app-name=paste-clipboard-image --icon=insert-image "Saved image" "$out"
    '';
  };

  pasteSymlink = pkgs.writeShellApplication {
    name = "paste-symlink";
    runtimeInputs = with pkgs; [
      wl-clipboard
      xclip
      python3
      libnotify
      coreutils
    ];
    text = ''
      fail() {
        notify-send --app-name=paste-symlink --icon=dialog-error "Paste link failed" "$1"
        exit 1
      }

      [ "$#" -ge 1 ] || fail "No destination"
      dest="$1"
      if [ ! -d "$dest" ]; then
        dest="$(dirname "$dest")"
      fi
      [ -d "$dest" ] || fail "Not a directory: $dest"

      uris="$(wl-paste --type text/uri-list 2>/dev/null || true)"
      if [ -z "$uris" ]; then
        uris="$(xclip -selection clipboard -t text/uri-list -o 2>/dev/null || true)"
      fi
      [ -n "$uris" ] || fail "Clipboard has no files"

      count="$(PASTE_URIS="$uris" python3 - "$dest" <<'PY'
import os
import sys
import urllib.parse

dest = sys.argv[1]
made = 0
for line in os.environ.get("PASTE_URIS", "").splitlines():
    raw = urllib.parse.unquote(line.strip())
    if not raw.startswith("file://"):
        continue
    src = raw[len("file://"):]
    if not src or not os.path.exists(src):
        continue
    name = os.path.basename(src.rstrip("/")) or "link"
    root, ext = os.path.splitext(name)
    target = os.path.join(dest, name)
    n = 1
    while os.path.lexists(target):
        target = os.path.join(dest, f"{root} ({n}){ext}")
        n += 1
    os.symlink(src, target)
    made += 1
if made == 0:
    sys.exit(1)
print(made)
PY
      )" || fail "No clipboard file could be linked"
      notify-send --app-name=paste-symlink --icon=insert-link "Created links" "$count"
    '';
  };
in
{
  home.packages = [
    copyImage
    copyPath
    pasteClipboardImage
    pasteSymlink
  ];

  # uca.xml used to be Thunar's own file (mode 600); home-manager owns it now.
  # The cost is that the "Configure custom actions" dialog can no longer save —
  # new actions go here instead. backupFileExtension = "backup" in
  # flake/system.nix preserves the old file as uca.xml.backup.
  #
  # "Open Terminal Here" is pre-existing and pairs with thunar-terminal.nix
  # (helpers.rc -> ~/.local/bin/thunar-open-terminal -> kitty). Don't drop it.
  home.file.".config/Thunar/uca.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <actions>
    <action>
    	<icon>utilities-terminal</icon>
    	<name>Open Terminal Here</name>
    	<submenu></submenu>
    	<unique-id>1777390765336062-1</unique-id>
    	<command>exo-open --working-directory %f --launch TerminalEmulator</command>
    	<description>Example for a custom action</description>
    	<range></range>
    	<patterns>*</patterns>
    	<startup-notify/>
    	<directories/>
    </action>
    <action>
    	<icon>edit-copy</icon>
    	<name>Copy as Image</name>
    	<submenu></submenu>
    	<unique-id>${copyImageId}</unique-id>
    	<command>${copyImage}/bin/copy-image %f</command>
    	<description>Put the image data itself on the clipboard (Wayland + X11), not the file path</description>
    	<range>1</range>
    	<patterns>*</patterns>
    	<image-files/>
    </action>
    <action>
    	<icon>edit-copy</icon>
    	<name>Copy Path</name>
    	<submenu></submenu>
    	<unique-id>copy-path-1</unique-id>
    	<command>${copyPath}/bin/copy-path %F</command>
    	<description>Copy the selected paths as text to Wayland and X11 clipboards</description>
    	<range>*</range>
    	<patterns>*</patterns>
    	<directories/>
    	<audio-files/>
    	<image-files/>
    	<other-files/>
    	<text-files/>
    	<video-files/>
    </action>
    <action>
    	<icon>insert-image</icon>
    	<name>Paste Clipboard Image</name>
    	<submenu></submenu>
    	<unique-id>paste-clipboard-image-1</unique-id>
    	<command>${pasteClipboardImage}/bin/paste-clipboard-image %f</command>
    	<description>Save the clipboard image into this folder as a PNG</description>
    	<range>*</range>
    	<patterns>*</patterns>
    	<directories/>
    </action>
    <action>
    	<icon>insert-link</icon>
    	<name>Paste as Link</name>
    	<submenu></submenu>
    	<unique-id>paste-symlink-1</unique-id>
    	<command>${pasteSymlink}/bin/paste-symlink %f</command>
    	<description>Symlink clipboard files into this folder</description>
    	<range>*</range>
    	<patterns>*</patterns>
    	<directories/>
    </action>
    </actions>
  '';

  # accels.scm is rewritten by Thunar itself on exit, so it cannot be a
  # read-only store symlink like uca.xml — patch the one line in instead.
  # Thunar's own dump preserves it from then on. Currently the file holds zero
  # active bindings (all defaults, all commented), so Ctrl+Shift+C is free.
  home.activation.thunarCopyImageAccel = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    accels="$HOME/.config/Thunar/accels.scm"
    line=${lib.escapeShellArg copyImageAccel}

    if [ -f "$accels" ]; then
      if ! ${pkgs.gnugrep}/bin/grep -qxF "$line" "$accels"; then
        ${pkgs.gnused}/bin/sed -i '/uca-action-${copyImageId}/d' "$accels"
        printf '%s\n' "$line" >> "$accels"
      fi
    else
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$accels")"
      printf '%s\n' "$line" > "$accels"
    fi
  '';
}
