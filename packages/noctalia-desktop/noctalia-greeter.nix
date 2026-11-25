# Noctalia Greeter 1.7.1.
#
# Based on the nixpkgs-unstable 1.7.0 recipe, upreved to the upstream v1.7.1 tag
# (2026-11-22). v1.7.1 added libinput (compositor), the libjxl_threads
# pkg-config module, and an unconditional find_program('python3') for its test
# wiring, all of which the 1.7.0 recipe does not provide.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  python3,
  wayland-scanner,
  bashNonInteractive,
  cairo,
  fontconfig,
  freetype,
  glib,
  harfbuzz,
  libGL,
  libglvnd,
  libinput,
  libjxl,
  librsvg,
  libwebp,
  libxkbcommon,
  libxml2,
  nlohmann_json,
  pango,
  stb,
  tomlplusplus,
  wayland,
  wayland-protocols,
  wlroots_0_20,
  nix-update-script,
}:

let
  # v1.7.1 tag commit; kept for provenance alongside the tag itself.
  rev = "2726e75375d95d5458d021f76c330ab14f6a5d03";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "noctalia-greeter";
  version = "1.7.1";

  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-greeter";
    tag = "v${finalAttrs.version}";
    hash = "sha256-6ojA9tFyaZO+jczG0KCP42xvCMbKVd5WLaAWvc5QGjA=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    python3
    wayland-scanner
  ];

  buildInputs = [
    bashNonInteractive
    cairo
    fontconfig
    freetype
    glib
    harfbuzz
    libGL
    libglvnd
    libinput
    libjxl
    librsvg
    libwebp
    libxkbcommon
    libxml2
    nlohmann_json
    pango
    stb
    tomlplusplus
    wayland
    wayland-protocols
    wlroots_0_20
  ];

  mesonBuildType = "release";

  passthru = {
    inherit rev;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "greetd greeter for Noctalia";
    homepage = "https://github.com/noctalia-dev/noctalia-greeter";
    license = lib.licenses.mit;
    mainProgram = "noctalia-greeter";
    platforms = lib.platforms.linux;
  };
})
