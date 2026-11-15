{
  pkgs,
  rustc,
  cargo,
}:
let
  # rust-toolchain.toml in this tree pins 1.99.1. Stable nixpkgs rustc is older.
  rustPlatform = pkgs.makeRustPlatform { inherit rustc cargo; };

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

    # Upstream tests need private fonts, a media library and a display.
    # The Mango rectangle tests live in window_detection::mango and are not
    # executed by this package build. Runtime coverage lives in
    # `passthru.tests.e2e` (private headless Mango; run manually).
    doCheck = false;

    postInstall = ''
      wrapProgram "$out/bin/mark-shot" --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.fontconfig
        ]
      }
    '';

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

    # Runtime suite: private D-Bus + private headless Mango at 2560x1600@1.5
    # with real capture/copy/save/editor runs. Build the script with
    #   nix build --no-write-lock-file --print-out-paths --impure --expr \
    #     '(import /path/to/repo/packages/mark-shot { pkgs = ...; rustc = ...; cargo = ...; }).passthru.tests.e2e'
    # then run `<out>/bin/mark-shot-e2e`. See tests/e2e/README.md.
    passthru.tests.e2e = pkgs.callPackage ./tests/e2e { markShot = package; };
  };
in
package
