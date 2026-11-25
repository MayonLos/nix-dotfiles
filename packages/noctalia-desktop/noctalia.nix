# Noctalia Shell 5.6.0.
#
# Adapted from upstream nix/package.nix at tag v5.6.0 (noctalia-dev/noctalia),
# which is authoritative for this release: 5.6.0 moved lock-screen
# authentication into the noctalia-pam-helper libexec binary, renamed the asset
# override variables and added the pam_service Meson option. nixpkgs-unstable
# only carries 5.4.1 and has no NixOS/Home Manager module.
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
  libGL,
  libglvnd,
  freetype,
  fontconfig,
  cairo,
  pango,
  harfbuzz,
  libxkbcommon,
  sdbus-cpp_2,
  systemd,
  pipewire,
  wireplumber,
  pam,
  curl,
  libwebp,
  libjxl,
  libsndfile,
  glib,
  polkit,
  librsvg,
  libqalculate,
  libxml2,
  md4c,
  libsecret,
  libsodium,
  stb,
  nlohmann_json,
  tomlplusplus,
  libical,
  jemalloc,
  makeWrapper,
  gitMinimal,
  gsettings-desktop-schemas,
  autoAddDriverRunpath,
  nix-update-script,
}:

let
  # v5.6.0 tag commit; baked into the binary as VCS_TAG because a GitHub
  # archive has no .git metadata for Meson's vcs_tag().
  rev = "a5444b9a2c2bc7c1aed5c59298a268e45de14055";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "noctalia";
  version = "5.6.0";

  src = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3Bt4df3TM7shQGxQbSDBjYk74oemNvRl4KT3DmLZGF4=";
  };

  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail "_git_revision_config.set('VCS_TAG', 'unknown')" "_git_revision_config.set('VCS_TAG', '${rev}')"
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    jemalloc
    makeWrapper
    autoAddDriverRunpath
  ];

  buildInputs = [
    wayland
    wayland-protocols
    libGL
    libglvnd
    freetype
    fontconfig
    cairo
    pango
    harfbuzz
    libxkbcommon
    sdbus-cpp_2
    systemd
    pipewire
    wireplumber
    pam
    curl
    libwebp
    libjxl
    libsndfile
    glib
    polkit
    librsvg
    libqalculate
    libxml2
    md4c
    libsecret
    libsodium
    # nixpkgs stb (0-unstable-2026-04-15) ships stb_image_resize2.h and
    # stb_image_write.h, so the override upstream keeps for older nixpkgs is
    # unnecessary here.
    stb
    nlohmann_json
    tomlplusplus
    libical
  ];

  mesonBuildType = "release";
  mesonFlags = [ "-Dtests=disabled" ];

  postFixup = ''
    wrapProgram $out/bin/noctalia \
      --prefix PATH : ${lib.makeBinPath [ gitMinimal ]} \
      --prefix XDG_DATA_DIRS : "${glib.getSchemaDataDirPath gsettings-desktop-schemas}"

    $out/bin/noctalia completions bash | install -D /dev/stdin $out/share/bash-completion/completions/noctalia
    $out/bin/noctalia completions zsh  | install -D /dev/stdin $out/share/zsh/site-functions/_noctalia
    $out/bin/noctalia completions fish | install -D /dev/stdin $out/share/fish/vendor_completions.d/noctalia.fish
  '';

  passthru = {
    inherit rev;
    updateScript = nix-update-script { };
  };

  meta = {
    description = "A sleek, customizable desktop shell crafted for Wayland";
    homepage = "https://noctalia.dev";
    changelog = "https://noctalia.dev/changelogs#v${finalAttrs.version}";
    license = with lib.licenses; [
      mit
      asl20 # material_color_utilities is Apache 2.0
    ];
    mainProgram = "noctalia";
    platforms = lib.platforms.linux;
  };
})
