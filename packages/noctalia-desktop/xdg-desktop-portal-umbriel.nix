# xdg-desktop-portal-umbriel, latest upstream main.
#
# Adapted from upstream nix/package.nix (noctalia-dev/xdg-desktop-portal-umbriel)
# with the revision bumped from the nixpkgs-unstable copy (5d16415, 2026-10-14)
# to latest main (426d3d4, 2026-11-24). The portal no longer uses a GTK4 share
# picker: it now draws with the in-tree noctalia-ui copy (EGL/GLES, pango,
# stb), so gtk4 is gone and the GL/text dependencies are required. dbus is moved
# to nativeBuildInputs because Meson resolves dbus-run-session at configure time
# when tests are enabled.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  sdbus-cpp_2,
  systemd,
  pipewire,
  libdrm,
  libgbm,
  cairo,
  tomlplusplus,
  nlohmann_json,
  libglvnd,
  libxkbcommon,
  freetype,
  fontconfig,
  pango,
  harfbuzz,
  glib,
  stb,
  autoAddDriverRunpath,
  libei,
  dbus,
  nix-update-script,
}:

let
  # Latest main commit (no tagged releases); 0.1.0 is the Meson project version.
  rev = "426d3d433d5a738d4abf01474c34487f884396ae";
in
stdenv.mkDerivation (_finalAttrs: {
  pname = "xdg-desktop-portal-umbriel";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "xdg-desktop-portal-umbriel";
    inherit rev;
    hash = "sha256-e9WsUzb8MxS4PtIt9ES87j0/fdvxO75Y/StvI8Ed1SQ=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    autoAddDriverRunpath
    dbus
  ];

  buildInputs = [
    wayland
    wayland-protocols
    sdbus-cpp_2
    systemd
    pipewire
    libdrm
    libgbm
    cairo
    tomlplusplus
    nlohmann_json
    libglvnd
    libxkbcommon
    freetype
    fontconfig
    pango
    harfbuzz
    glib
    stb
  ];

  mesonBuildType = "release";

  doCheck = true;
  checkInputs = [ libei ];

  passthru = {
    inherit rev;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "xdg-desktop-portal backend for the Umbriel compositor";
    homepage = "https://github.com/noctalia-dev/xdg-desktop-portal-umbriel";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
