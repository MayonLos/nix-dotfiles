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
      #   wl-copy -> native Wayland clients (QQ, Zen, Typora, everything niri)
      #   xclip   -> XWayland clients (wechat-uos pins QT_QPA_PLATFORM=xcb)
      # xwayland-satellite is supposed to keep those two in sync, but it reads
      # the Wayland selection through the seat's wl_data_device, which requires
      # keyboard focus — so a copy performed while a Wayland window is focused
      # is not reliably visible to X11 clients. Writing both sides directly
      # sidesteps the whole question.
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
in
{
  home.packages = [ copyImage ];

  # uca.xml used to be Thunar's own file (mode 600); home-manager owns it now.
  # The cost is that the "Configure custom actions" dialog can no longer save —
  # new actions go here instead. backupFileExtension = "backup" in
  # flake/system.nix preserves the old file as uca.xml.backup.
  #
  # "Open Terminal Here" is pre-existing and pairs with thunar-terminal.nix
  # (helpers.rc -> foot). Don't drop it.
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
