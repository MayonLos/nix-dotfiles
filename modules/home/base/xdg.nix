{ lib, ... }:
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
  xdg.mimeApps = {
    enable = true;
    # Keep Zathura as the default while offering Okular for richer GUI
    # annotation and document navigation when explicitly requested.
    associations.added = {
      "application/pdf" = [ "org.kde.okular.desktop" ];
    };
    defaultApplications = (lib.genAttrs imageTypes (_: [ "swayimg.desktop" ])) // {
      "application/pdf" = [ "org.pwmt.zathura-pdf-mupdf.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/quicktime" = [ "mpv.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
    };
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
      window = "#1f2329ff";
      transparency = "grid";
      scale = "optimal";
    };
    gallery = {
      size = 180;
      padding = 8;
      aspect = "fit";
      window = "#1f2329ff";
      background = "#282c34ff";
      select = "#323844ff";
      border_color = "#4fa6edff";
      border_width = 3;
    };
    list = {
      all = "yes";
      order = "numeric";
      recursive = "no";
    };
    font = {
      color = "#a0a8b7ff";
      background = "#181b20d0";
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
