# Umbriel compositor, latest upstream main.
#
# Adapted from upstream nix/package.nix (noctalia-dev/umbriel) with the revision
# bumped from the nixpkgs-unstable copy (0a22bd2, 2026-11-09) to the latest main
# (b56b66c, 2026-11-24). The newer revision added the GlobalShortcuts protocol
# bridge, ICC characterization (lcms2, already a nixpkgs dependency) and the
# config override store; the Meson dependency set is otherwise unchanged.
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
  wlroots_0_20,
  libxkbcommon,
  libinput,
  libei,
  systemd,
  pixman,
  cairo,
  pango,
  libGL,
  libdrm,
  libdisplay-info,
  libgbm,
  libxcb,
  libxcb-wm,
  lcms2,
  jemalloc,
  tomlplusplus,
  nlohmann_json,
  xwayland,
  makeBinaryWrapper,
  nix-update-script,
}:

let
  rev = "b56b66ce66b4cf84d34e522d3ad63a82b215ccd9";
in
stdenv.mkDerivation (_finalAttrs: {
  pname = "umbriel";
  version = "0-unstable-2026-11-24";

  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "umbriel";
    # No tagged releases yet.
    inherit rev;
    hash = "sha256-Pfnu8U7taFHVr88V6dK6LOR+ANCOgfVCVn4aQ7DVUsc=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    makeBinaryWrapper
    meson
    ninja
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    wayland
    wayland-protocols
    wlroots_0_20
    libxkbcommon
    libinput
    libei
    # libudev for native DRM policy support and sd-bus for the localed keymap.
    systemd
    pixman
    tomlplusplus
    libGL
    nlohmann_json
    libdrm
    libdisplay-info
    libgbm
    libxcb # includes xcb-randr
    libxcb-wm
    lcms2
    jemalloc
    cairo
    pango
  ];

  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail "umbriel_git_revision_config.set('VCS_TAG', 'unknown')" "umbriel_git_revision_config.set('VCS_TAG', '${rev}')"
  '';

  mesonBuildType = "release";
  mesonFlags = [ (lib.mesonEnable "tests" false) ];

  postInstall = ''
    if [ -f "$out/share/wayland-sessions/umbriel.desktop" ]; then
      substituteInPlace "$out/share/wayland-sessions/umbriel.desktop" \
        --replace-fail 'Exec=start-umbriel' "Exec=$out/bin/start-umbriel"
    fi
    wrapProgram $out/bin/umbriel \
      --prefix PATH : ${lib.makeBinPath [ xwayland ]}
  '';

  passthru = {
    inherit rev;
    providedSessions = [ "umbriel" ];
    updateScript = nix-update-script { };
  };

  meta = {
    description = "A Wayland compositor built on wlroots and SceneFX";
    homepage = "https://docs.noctalia.dev/umbriel/";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "umbriel";
  };
})
