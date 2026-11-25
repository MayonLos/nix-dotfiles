# Luciole 0.1.0 (in development upstream), latest main.
#
# Adapted from upstream nix/package.nix (noctalia-dev/luciole), which is the
# authoritative packaging recipe. Luciole has no nixpkgs package. The upstream
# recipe patches in a Glycin-enabled GdkPixbuf and rebuilds librsvg against it so
# image loading happens in sandboxed loader processes; the same override is kept
# here. nixpkgs-unstable stb already provides stb_image_resize2.h, so the
# upstream stb override is dropped.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  meson,
  ninja,
  pkg-config,
  python3,
  wayland-scanner,
  wayland,
  wayland-protocols,
  libglvnd,
  libxkbcommon,
  freetype,
  fontconfig,
  cairo,
  glib,
  glib-networking,
  gsettings-desktop-schemas,
  dconf,
  dbus,
  gvfs,
  curl,
  libxml2,
  pango,
  harfbuzz,
  libpng,
  libarchive,
  xz,
  acl,
  libwebp,
  librsvg,
  gdk-pixbuf,
  libglycin,
  glycin-loaders,
  stb,
  ffmpeg,
  ffmpegthumbnailer,
  poppler-utils,
  _7zz,
  nlohmann_json,
  tomlplusplus,
  autoAddDriverRunpath,
  makeWrapper,
  adwaita-icon-theme,
  shared-mime-info,
  xdg-terminal-exec,
  nix-update-script,
  buildRevision ? "95ccd465b24e616bbcf05a6d753e1e75b7432310",
}:

let
  rev = "95ccd465b24e616bbcf05a6d753e1e75b7432310";

  # Upstream pins GdkPixbuf 2.44.6 because the nixpkgs collection it was tested
  # against exposes the Glycin 2.1 API, while 2.44.8 requires Glycin 2.2.
  pixbufWithGlycin = gdk-pixbuf.overrideAttrs (previous: {
    version = "2.44.6";
    src = fetchurl {
      url = "https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.6.tar.xz";
      hash = "sha256-FAwtC4mfz4U+6SsmNzydwijbzeCCCkJGaT9DKKJ0Zvo=";
    };
    buildInputs = (previous.buildInputs or [ ]) ++ [
      libglycin
      glycin-loaders
      shared-mime-info
    ];
    preBuild = (previous.preBuild or "") + ''
      export XDG_DATA_DIRS="${glycin-loaders}/share:${shared-mime-info}/share:''${XDG_DATA_DIRS:-}"
    '';
    mesonFlags =
      builtins.filter (
        flag:
        !(lib.any (name: lib.hasPrefix "-D${name}=" flag) [
          "glycin"
          "builtin_loaders"
          "png"
          "jpeg"
          "gif"
          "tiff"
          "others"
          "legacy_xpm"
        ])
      ) previous.mesonFlags
      ++ [
        "-Dglycin=enabled"
        "-Dbuiltin_loaders=glycin"
        "-Dpng=disabled"
        "-Djpeg=disabled"
        "-Dgif=disabled"
        "-Dtiff=disabled"
        "-Dothers=disabled"
        "-Dlegacy_xpm=disabled"
      ];
  });
  svgWithGlycin = librsvg.override { gdk-pixbuf = pixbufWithGlycin; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "luciole";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "luciole";
    inherit rev;
    hash = "sha256-Fd+LQSDITobK36lH9/tvzzQNODVCcf2m+YEtrIThGjk=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    python3
    wayland-scanner
    autoAddDriverRunpath
    makeWrapper
  ];

  nativeCheckInputs = [
    dbus
    glib
  ];

  buildInputs = [
    wayland
    wayland-protocols
    libglvnd
    libxkbcommon
    freetype
    fontconfig
    cairo
    glib
    curl
    libxml2
    pango
    harfbuzz
    libpng
    libarchive
    xz
    acl
    libwebp
    pixbufWithGlycin
    svgWithGlycin
    glycin-loaders
    stb
    nlohmann_json
    tomlplusplus
  ];

  # GNU LTO archives need the compiler's plugin-aware tools.
  preConfigure = lib.optionalString stdenv.cc.isGNU ''
    export AR="${stdenv.cc.cc}/bin/gcc-ar"
    export RANLIB="${stdenv.cc.cc}/bin/gcc-ranlib"
  '';

  mesonBuildType = "release";
  mesonFlags = [
    "-Dtests=disabled"
    (lib.mesonOption "build_revision" buildRevision)
  ];

  postFixup = ''
    wrapProgram "$out/bin/luciole" \
      --suffix PATH : "${
        lib.makeBinPath [
          xdg-terminal-exec
          ffmpeg
          ffmpegthumbnailer
          poppler-utils
          _7zz
        ]
      }" \
      --suffix GIO_EXTRA_MODULES : "${
        lib.makeSearchPath "lib/gio/modules" [
          gvfs
          glib-networking
          dconf.lib
        ]
      }" \
      --suffix XDG_DATA_DIRS : "${glib.getSchemaDataDirPath gsettings-desktop-schemas}:${
        lib.makeSearchPath "share" [
          adwaita-icon-theme
          shared-mime-info
          glycin-loaders
        ]
      }"
  '';

  passthru = {
    inherit rev;
    glycinLoaders = glycin-loaders;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Luciole, a native Wayland file manager using Noctalia rendering and controls (in development)";
    homepage = "https://github.com/noctalia-dev/luciole";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = finalAttrs.pname;
  };
})
