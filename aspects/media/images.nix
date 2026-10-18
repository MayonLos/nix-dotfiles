{ palette }:
{ lib, pkgs, ... }:
let
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
in
{
  home.packages = [
    pkgs.swayimg
    pkgs.libheif
  ];
  xdg.mimeApps = {
    enable = true;
    defaultApplications = lib.genAttrs imageTypes (_: [ "swayimg.desktop" ]);
  };

  # The packaged entry has NoDisplay=true. Override the same desktop ID so
  # the viewer is also discoverable in Noctalia and Open With menus.
  xdg.desktopEntries.swayimg = {
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
  # apply to 4.7. Unspecified options and bindings retain packaged defaults.
  xdg.configFile."swayimg/config".text = lib.generators.toINI { } {
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
      border_width = 3;
    };
    list = {
      all = "yes";
      order = "numeric";
      recursive = "no";
    };
    font = {
      name = palette.fonts.sans;
      size = 11;
      color = "${palette.brightFg}ff";
      background = "${palette.deep}d0";
    };
    "info.viewer" = {
      top_left = "name";
      top_right = "index";
      bottom_left = "imagesize,scale,frame";
      bottom_right = "status";
    };
    "keys.viewer" = {
      Left = "prev_file";
      Right = "next_file";
      h = "prev_file";
      l = "next_file";
      j = "step_down 10";
      k = "step_up 10";
      ScrollUp = "zoom +10 mouse";
      ScrollDown = "zoom -10 mouse";
      MouseRight = "mode gallery";
      "Shift+Delete" = "none";
    };
    "keys.gallery"."Shift+Delete" = "none";
  };
}
