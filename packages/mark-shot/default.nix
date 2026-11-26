{
  pkgs,
  rustc,
  cargo,
}:
let
  inherit (pkgs) lib;

  # Upstream release, not a vendored copy. Source is the v0.2.4 tag and the
  # fixes that only apply to this repository live in ./patches (see README.md
  # for why each one exists). Packaging stays repository-owned: the media
  # library is built from pinned LGPL sources below, and the wrapper provides
  # the NixOS paths the user-installed OCR runtime and the recording backends
  # dlopen at runtime.
  version = "0.2.4";
  revision = "dbef0b5f5391fac9031443ed074e49bc1dd836d0";

  upstream = pkgs.fetchFromGitHub {
    owner = "jswysnemc";
    repo = "mark-shot";
    rev = revision;
    hash = "sha256-vGfWT7NejcGhEigIZlDgBoACUHCmwkIwVxrE1kuJ6oo=";
  };

  source = pkgs.applyPatches {
    name = "mark-shot-${version}-patched";
    src = upstream;
    patches = [
      # mmsg window rectangles: upstream has no Mango backend.
      ./patches/0001-mango-window-detection.patch
      # Captured frame pixels are the only grid on fractional-scale outputs.
      ./patches/0002-capture-pixel-grid.patch
      # Tolerate malformed config fields instead of dropping the whole file.
      ./patches/0003-config-recovery.patch
      # One Dark palette for the editor chrome.
      ./patches/0004-one-dark-theme.patch
    ];
  };

  # rust-toolchain.toml in the upstream tree pins 1.99.1. Stable nixpkgs rustc
  # is older, so the compiler comes from the repository's unstable instance
  # while system libraries stay on `pkgs` (stable).
  rustPlatform = pkgs.makeRustPlatform { inherit rustc cargo; };

  # In-process recording/export library. `crates/shot-media` dlopens
  # media/libmarkshot-media.so from the executable's directory and cannot use a
  # GPL FFmpeg, so media.nix builds its own LGPL-only FFmpeg 9.0.2 plus
  # OpenH264/nv-codec-headers from the native sources in the patched tree.
  media = import ./media.nix {
    inherit pkgs;
    src = source;
  };

  # ONNX Runtime is downloaded into the user's data directory at runtime
  # (`~/.local/share/mark-shot/runtime`), so it is not linked or patched by
  # Nix. Its NEEDED entries include libstdc++.so.6 and libgcc_s.so.1, which
  # NixOS deliberately keeps out of a global /usr/lib; without these store
  # paths on the loader search path `ort::init_from` can never dlopen the
  # user-installed library. This is only the C/C++ support runtime -- the
  # recording/export FFmpeg remains the separate LGPL build in media.nix.
  # libgcc can alias the compiler's lib output, hence `unique`.
  ortRuntime = lib.makeLibraryPath (
    lib.unique [
      pkgs.stdenv.cc.cc.lib
      pkgs.libgcc.lib
    ]
  );

  # Runtime library directories for the in-process media backends: the media
  # library dlopens libpulse and the graphics driver directory holds the VAAPI
  # driver and the NVIDIA user-space libs that FFmpeg's dynload shims resolve.
  mediaRuntime = "/run/opengl-driver/lib:${lib.makeLibraryPath [ pkgs.libpulseaudio ]}";

  package = rustPlatform.buildRustPackage {
    pname = "mark-shot";
    inherit version;
    src = source;
    # Cargo.lock lives in the fetched tree; a vendor hash keeps flake
    # evaluation pure (no import-from-derivation of the lock file).
    cargoHash = "sha256-EPtSj+NTjXxvG9dAmT8Fus+0B5Duuph0a3OxIlLnt9k=";

    nativeBuildInputs = with pkgs; [
      pkg-config
      clang
      makeWrapper
      patchelf
    ];
    buildInputs = with pkgs; [
      libclang
      wayland
      libxkbcommon
      libxcb
      pipewire
      openssl
      fontconfig
      freetype
      libva
      libdrm
      libgbm
      libpulseaudio
    ];
    LIBCLANG_PATH = "${lib.getLib pkgs.libclang}/lib";

    # Upstream tests need private reference fonts, the media library and a
    # real display. Runtime coverage is `passthru.tests.e2e` (private headless
    # Mango at 2560x1600@1.5) and is run manually; the Nix package stays lean
    # so a system rebuild does not run the whole workspace suite.
    doCheck = false;

    postInstall = ''
      # crates/shot-media/src/lib.rs loads `media/libmarkshot-media.so` relative
      # to the running executable (or an absolute MARK_SHOT_MEDIA_LIBRARY), so
      # install it beside the real binary exactly like the upstream release
      # tarballs do.
      install -Dm755 ${media.library}/lib/mark-shot/media/libmarkshot-media.so \
        "$out/bin/media/libmarkshot-media.so"
      install -d "$out/share/licenses/mark-shot-media"
      cp -a ${media.library}/share/licenses/mark-shot-media/. \
        "$out/share/licenses/mark-shot-media/"
      install -Dm644 ${source}/packaging/desktop/io.github.jswysnemc.MarkShot.desktop \
        "$out/share/applications/io.github.jswysnemc.MarkShot.desktop"
      install -Dm644 ${source}/packaging/desktop/io.github.jswysnemc.MarkShot.metainfo.xml \
        "$out/share/metainfo/io.github.jswysnemc.MarkShot.metainfo.xml"
      install -Dm644 ${source}/assets/hicolor/scalable/apps/mark-shot.svg \
        "$out/share/icons/hicolor/scalable/apps/io.github.jswysnemc.MarkShot.svg"
      install -Dm644 ${source}/LICENSE-MIT "$out/share/licenses/mark-shot/LICENSE-MIT"
      install -Dm644 ${source}/LICENSE-APACHE "$out/share/licenses/mark-shot/LICENSE-APACHE"
      # Provenance for bug reports: the exact upstream commit plus a marker that
      # this build carries repository patches.
      install -d "$out/share/mark-shot"
      printf '%s\n' "upstream ${revision} (v${version}) + repository patches" \
        > "$out/share/mark-shot/SOURCE-COMMIT"
      wrapProgram "$out/bin/mark-shot" \
        --prefix PATH : ${lib.makeBinPath [ pkgs.fontconfig ]} \
        --prefix LD_LIBRARY_PATH : "${ortRuntime}:${mediaRuntime}"
    '';

    # The package fixup runs patchelf --shrink-rpath over every ELF file in
    # $out, including the copied media library, which drops the PulseAudio
    # directory again (shot-media dlopens libpulse.so.0 instead of linking it).
    # Restore it after fixup; see media.nix for the same step on the library's
    # own output.
    postFixup = ''
      patchelf --add-rpath "${lib.makeLibraryPath [ pkgs.libpulseaudio ]}" \
        "$out/bin/media/libmarkshot-media.so"
    '';

    passthru = {
      inherit media source version;
      # Runtime suite: private D-Bus + private headless Mango at 2560x1600@1.5
      # with real capture/copy/save/editor runs. Build it with
      #   nix build --no-write-lock-file --print-out-paths --impure --expr \
      #     '(import ./packages/mark-shot { pkgs = ...; rustc = ...; cargo = ...; }).passthru.tests.e2e'
      # then run `<out>/bin/mark-shot-e2e`. See e2e/README.md.
      tests.e2e = pkgs.callPackage ./e2e {
        markShot = package;
        upstreamScripts = "${source}/scripts";
      };
    };

    meta = {
      description = "Screenshot, annotation and scrolling capture tool (upstream source plus repository fixes)";
      homepage = "https://github.com/jswysnemc/mark-shot";
      license = with lib.licenses; [
        mit
        asl20
      ];
      mainProgram = "mark-shot";
      platforms = lib.platforms.linux;
    };
  };
in
package
