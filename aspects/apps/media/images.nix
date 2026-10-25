{ palette }:
{ lib, pkgs, ... }:
let
  swayimg = import ./swayimg-package.nix { inherit pkgs; };
  # Formats decoded by the locked swayimg 4.7 build. Keep explicit MIME types:
  # image/* is not a wildcard in mimeapps.list.
  imageTypes = [
    "image/avif"
    "image/bmp"
    "image/gif"
    "image/heic"
    "image/heif"
    "image/jpeg"
    "image/jpg"
    "image/jxl"
    "image/pbm"
    "image/pjpeg"
    "image/png"
    "image/svg+xml"
    "image/tiff"
    "image/webp"
    "image/x-bmp"
    "image/x-exr"
    "image/x-png"
    "image/x-portable-anymap"
    "image/x-portable-bitmap"
    "image/x-portable-graymap"
    "image/x-portable-pixmap"
    "image/x-targa"
    "image/x-tga"
  ];

  trashImage = pkgs.writeShellApplication {
    name = "swayimg-trash";
    runtimeInputs = [
      pkgs.zenity
      pkgs.trash-cli
      pkgs.coreutils
    ];
    text = ''
      image="''${1:?swayimg did not provide an image path}"
      if [ ! -f "$image" ]; then
        zenity --error --title='Swayimg' --text='The current image is no longer available.'
        exit 1
      fi
      if zenity --question --title='Move image to Trash?' \
        --text="Move ‘$(basename -- "$image")’ to the Trash?" \
        --ok-label='Move to Trash' --cancel-label='Keep image'; then
        exec trash-put -- "$image"
      fi
    '';
  };

  copyImage = pkgs.writeShellApplication {
    name = "swayimg-copy-image";
    runtimeInputs = [
      pkgs.imagemagick
      pkgs.wl-clipboard
      pkgs.xclip
    ];
    text = ''
      image="''${1:?swayimg did not provide an image path}"
      [ -f "$image" ] || exit 1
      if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
        convert "''${image}[0]" PNG:- | wl-copy --type image/png
      elif [ -n "''${DISPLAY:-}" ]; then
        convert "''${image}[0]" PNG:- | xclip -selection clipboard -t image/png -i
      else
        echo 'No Wayland or X11 clipboard is available.' >&2
        exit 1
      fi
    '';
  };

  openInGimp = pkgs.writeShellApplication {
    name = "swayimg-open-in-gimp";
    runtimeInputs = [
      pkgs.gimp
      pkgs.util-linux
    ];
    text = ''
      image="''${1:?swayimg did not provide an image path}"
      [ -f "$image" ] || exit 1
      # Detach so opening GIMP does not block Swayimg's action loop.
      setsid -f gimp "$image"
    '';
  };
in
{
  home.packages = [
    swayimg
    trashImage
    copyImage
    openInGimp
  ];
  xdg = {
    mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs imageTypes (_: [ "swayimg.desktop" ]);
    };

    # The packaged entry has NoDisplay=true. Override the same desktop ID so
    # the viewer is also discoverable in Noctalia and Open With menus.
    desktopEntries.swayimg = {
      name = "Swayimg";
      genericName = "Image Viewer";
      comment = "Browse images and thumbnails";
      exec = "swayimg %F";
      icon = "swayimg";
      terminal = false;
      categories = [
        "Graphics"
        "Viewer"
      ];
      mimeType = imageTypes;
      settings.StartupNotify = "false";
    };

    # The pinned release uses INI; upstream's newer Lua configuration does not
    # apply to 4.7. Bindings used for destructive or external actions are
    # explicit, and deletion is recoverable and confirmed before it can run.
    configFile."swayimg/config".text = lib.generators.toINI { } {
      general = {
        size = "1280,800";
        overlay = "no";
      };
      viewer = {
        window = "${palette.bg}ff";
        transparency = "grid";
        scale = "optimal";
      };
      gallery = {
        size = 180;
        padding = 8;
        aspect = "fit";
        window = "${palette.bg}ff";
        background = "${palette.surface}ff";
        select = "${palette.selection}ff";
        border_color = "${palette.blue}ff";
        border_width = 2;
      };
      list = {
        all = "yes";
        order = "numeric";
        recursive = "no";
        fsmon = "yes";
      };
      font = {
        name = palette.fonts.sans;
        size = 11;
        color = "${palette.brightFg}ff";
        background = "${palette.deep}ff";
      };
      info = {
        show = "yes";
        # The locked default hides info after 5 seconds. Keep the bottom
        # filename/dimensions/zoom/index visible while browsing.
        info_timeout = 0;
      };
      "info.viewer" = {
        top_left = "none";
        top_right = "none";
        bottom_left = "name,imagesize,scale";
        bottom_right = "index";
      };
      "keys.viewer" = {
        Left = "prev_file";
        Right = "next_file";
        h = "prev_file";
        l = "next_file";
        j = "step_down 10";
        k = "step_up 10";
        r = "rotate_right";
        "Shift+r" = "rotate_left";
        f = "zoom fit";
        "1" = "zoom real";
        # The package-local patch adds %q, which shell-quotes arbitrary paths.
        Delete = "exec ${trashImage}/bin/swayimg-trash %q";
        "Shift+Delete" = "none";
        d = "none";
        "Ctrl+c" = "exec ${copyImage}/bin/swayimg-copy-image %q";
        "Ctrl+g" = "exec ${openInGimp}/bin/swayimg-open-in-gimp %q";
        ScrollUp = "zoom +10 mouse";
        ScrollDown = "zoom -10 mouse";
        MouseRight = "mode gallery";
      };
      "keys.gallery" = {
        Delete = "none";
        "Shift+Delete" = "none";
        d = "none";
      };
    };
  };

}
