{
  pkgs,
  rustc,
  cargo,
}:
let
  # rust-toolchain.toml in this tree pins 1.99.1. Stable nixpkgs rustc is older.
  rustPlatform = pkgs.makeRustPlatform { inherit rustc cargo; };
  # In-process recording/export library. `crates/shot-media` dlopens
  # media/libmarkshot-media.so from the executable's directory and cannot use
  # a GPL FFmpeg, so media.nix builds its own LGPL-only FFmpeg 9.0.2 plus
  # OpenH264/nv-codec-headers. See media.nix for the pinned sources and layout.
  media = import ./media.nix { inherit pkgs; };

  package = rustPlatform.buildRustPackage {
    pname = "mark-shot";
    version = "0.2.0";
    src = pkgs.lib.cleanSource ./.;
    cargoLock.lockFile = ./Cargo.lock;

    nativeBuildInputs = with pkgs; [
      pkg-config
      clang
      nasm
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
      libva
      libdrm
      libgbm
      libpulseaudio
    ];
    LIBCLANG_PATH = "${pkgs.lib.getLib pkgs.libclang}/lib";

    # Upstream tests need private fonts, a media library and a display. The
    # Mango rectangle tests live in window_detection::mango and are not
    # executed by this package build. Runtime coverage lives in
    # `passthru.tests.e2e` (private headless Mango; run manually).
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
      wrapProgram "$out/bin/mark-shot" --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.fontconfig
        ]
      }
    '';

    # The package fixup runs patchelf --shrink-rpath over every ELF file in
    # $out, including the copied media library, which drops the PulseAudio
    # directory again (shot-media dlopens libpulse.so.0 instead of linking it).
    # Restore it after fixup; see media.nix for the same step on the library's
    # own output.
    postFixup = ''
      patchelf --add-rpath "${pkgs.lib.makeLibraryPath [ pkgs.libpulseaudio ]}" \
        "$out/bin/media/libmarkshot-media.so"
    '';

    passthru = {
      inherit media;
      # Runtime suite: private D-Bus + private headless Mango at 2560x1600@1.5
      # with real capture/copy/save/editor runs. Build the script with
      #   nix build --no-write-lock-file --print-out-paths --impure --expr \
      #     '(import /path/to/repo/packages/mark-shot { pkgs = ...; rustc = ...; cargo = ...; }).passthru.tests.e2e'
      # then run `<out>/bin/mark-shot-e2e`. See tests/e2e/README.md.
      tests.e2e = pkgs.callPackage ./tests/e2e { markShot = package; };
    };

    meta = {
      description = "Local Rust screenshot, annotation and scrolling capture tool";
      homepage = "https://github.com/jswysnemc/mark-shot";
      license = with pkgs.lib.licenses; [
        mit
        asl20
      ];
      mainProgram = "mark-shot";
      platforms = pkgs.lib.platforms.linux;
    };
  };
in
package
