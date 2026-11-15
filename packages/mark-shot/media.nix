# In-process media library for mark-shot, built from pinned upstream sources.
#
# `crates/shot-media` loads `media/libmarkshot-media.so` next to the executable
# (or the absolute path in `MARK_SHOT_MEDIA_LIBRARY`) and only uses the stable
# `ms_*` ABI exported by `crates/shot-media/native/*.c`. Recording and MKV/GIF
# export are linked into that one shared object, so FFmpeg is linked statically
# and must be an LGPL-only configuration: no GPL and no nonfree components. The
# pins, components and configure flags mirror `scripts/media/build-libraries.sh`
# in this vendored tree so the Nix output matches the release media bundle:
# OpenH264 2.6.0 and nv-codec-headers n13.0.19.0 are exactly the versions the
# script downloads. FFmpeg is 9.0.2, the current patch release of the 9.0
# series the script pins (9.0); the patch release keeps the same configure
# interface and component set. Versions and digests are fixed here; do not use
# the nixpkgs `ffmpeg`, which is a GPL build (x264/x265).
#
# nv-codec-headers is NOT the newer 9.1.23.1 from git.videolan.org that some
# nixpkgs channels package: FFmpeg 9.0.2's configure requires
# `ffnvcodec >= 12.1.14.0` and the renumbered headers advertise 9.1.23.1, which
# would silently disable the NVENC encoders. The GitHub tag pinned by the
# vendored script satisfies the check and keeps h264_nvenc available.
{ pkgs }:
let
  inherit (pkgs) lib stdenv fetchurl;
  inherit (pkgs) nasm pkg-config patchelf;

  # OpenH264 names its arm64 target `arm64`, every other target after `uname -m`.
  openh264Arch =
    if stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if stdenv.hostPlatform.isAarch64 then
      "arm64"
    else
      throw "mark-shot media: unsupported OpenH264 architecture ${stdenv.hostPlatform.system}";

  openh264 = stdenv.mkDerivation {
    pname = "openh264";
    version = "2.6.0";
    src = fetchurl {
      url = "https://codeload.github.com/cisco/openh264/tar.gz/refs/tags/v2.6.0";
      # codeload URLs end in the tag name, so name the archive explicitly for
      # the stdenv unpacker.
      name = "openh264-2.6.0.tar.gz";
      hash = "sha256-VYVErTWCg6erKTDWmpzt35E/SlHum/G/ueN3Mir4Gmk=";
    };

    nativeBuildInputs = [ nasm ];

    # Upstream builds the static archive with PIC so it can be linked into the
    # private shared object. `install-static` also installs openh264.pc, which
    # FFmpeg's configure uses for `--enable-libopenh264`.
    makeFlags = [
      "ARCH=${openh264Arch}"
      "BUILDTYPE=Release"
      "ENABLEPIC=Yes"
      "PREFIX=${placeholder "out"}"
    ];
    buildPhase = ''
      runHook preBuild
      make -j"$NIX_BUILD_CORES" libraries
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      make install-static ARCH=${openh264Arch} PREFIX="$out"
      install -Dm644 LICENSE "$out/share/licenses/openh264/LICENSE"
      runHook postInstall
    '';

    meta = {
      description = "OpenH264 video codec (static library for mark-shot)";
      homepage = "https://www.openh264.org/";
      license = lib.licenses.bsd2;
      platforms = lib.platforms.linux;
    };
  };

  nv-codec-headers = stdenv.mkDerivation {
    pname = "nv-codec-headers";
    version = "n13.0.19.0";
    src = fetchurl {
      url = "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz";
      hash = "sha256-htFdGnwKxzoOr9/Fe+v+un2oJkWVv1Mc9NjbHCKUARY=";
    };
    dontBuild = true;
    makeFlags = [ "PREFIX=${placeholder "out"}" ];
    installPhase = ''
      runHook preInstall
      make install PREFIX="$out"
      # This tag ships no LICENSE file; keep the upstream README for provenance.
      install -Dm644 README "$out/share/licenses/nv-codec-headers/README"
      runHook postInstall
    '';
    meta = {
      description = "NVIDIA video codec SDK headers for FFmpeg NVENC";
      homepage = "https://github.com/FFmpeg/nv-codec-headers";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };

  # FFmpeg 9.0 configured exactly like scripts/media/build-libraries.sh: a
  # static, PIC, program-free LGPL build with only the components shot-media
  # uses. `--disable-autodetect` keeps every other system library out, and the
  # explicit component list is copied from the upstream script. OpenH264 and
  # nv-codec-headers are the only codec backends: x264/x265 (GPL) are absent.
  ffmpeg = stdenv.mkDerivation {
    pname = "ffmpeg-lgpl";
    version = "9.0.2";
    src = fetchurl {
      url = "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz";
      hash = "sha256-jDhQKD6yX6AmSCB4oEBR4L4XNHsJ74GghJvsFaluAC4=";
    };

    nativeBuildInputs = [
      pkg-config
      nasm
    ];
    buildInputs = [
      openh264
      nv-codec-headers
      pkgs.libva
      pkgs.libdrm
      pkgs.libgbm
      # Compile-time CUDA headers only: FFmpeg loads libcuda/libnvidia-encode
      # at runtime through its own dynload shims, so no CUDA library is linked
      # or added to the media library closure.
      pkgs.cudaPackages.cuda_cudart
    ];

    configureFlags = [
      "--disable-debug"
      "--disable-doc"
      "--disable-autodetect"
      "--disable-everything"
      "--disable-programs"
      "--disable-network"
      "--disable-avdevice"
      "--disable-shared"
      "--enable-static"
      "--enable-pic"
      "--enable-avfilter"
      "--enable-swscale"
      "--enable-swresample"
      "--enable-decoder=h264,aac"
      "--enable-parser=h264,aac"
      "--enable-encoder=gif,aac"
      "--enable-demuxer=mov,matroska"
      "--enable-muxer=mp4,matroska,gif"
      "--enable-protocol=file"
      "--enable-bsf=extract_extradata,h264_mp4toannexb"
      "--enable-filter=buffer,buffersink,scale,fps,format,split,palettegen,paletteuse"
      "--enable-libopenh264"
      "--enable-encoder=libopenh264,h264_vaapi,h264_nvenc"
      "--enable-vaapi"
      "--enable-ffnvcodec"
      "--enable-nvenc"
      "--enable-cuda"
      "--pkg-config-flags=--static"
      "--extra-cflags=-fno-lto"
      "--extra-ldflags=-fno-lto"
      "--prefix=${placeholder "out"}"
    ];

    enableParallelBuilding = true;
    doCheck = false;

    postInstall = ''
      install -Dm644 COPYING.LGPLv2.1 "$out/share/licenses/ffmpeg-lgpl/COPYING.LGPLv2.1"
      # Fail the build if the configuration ever becomes GPL or nonfree.
      if grep -Eq '^#define CONFIG_(GPL|NONFREE) 1' config.h; then
        echo "mark-shot media: FFmpeg was configured with GPL/nonfree components" >&2
        exit 1
      fi
      install -Dm644 config.h "$out/share/mark-shot-media/FFMPEG-CONFIG.h"
      install -Dm644 config_components.h "$out/share/mark-shot-media/FFMPEG-CONFIG-COMPONENTS.h"
      install -Dm644 ffbuild/config.mak "$out/share/mark-shot-media/FFMPEG-CONFIG.mak"
    '';

    meta = {
      description = "LGPL-only static FFmpeg 9.0.2 libraries for mark-shot media";
      homepage = "https://ffmpeg.org/";
      license = lib.licenses.lgpl21Plus;
      platforms = lib.platforms.linux;
    };
  };

  library = stdenv.mkDerivation {
    pname = "mark-shot-media";
    version = "0.2.0";
    src = ./crates/shot-media/native;

    nativeBuildInputs = [
      pkg-config
      patchelf
    ];
    buildInputs = [
      ffmpeg
      openh264
      pkgs.libgbm
      pkgs.libva
      pkgs.libdrm
      pkgs.libpulseaudio
    ];

    dontConfigure = true;
    enableParallelBuilding = false;

    buildPhase = ''
      runHook preBuild
      media_cflags=$(pkg-config --cflags libavcodec libavformat libavutil libavfilter libswscale libswresample)
      media_libs=$(pkg-config --static --libs libavformat libavcodec libavfilter libswscale libswresample libavutil)
      mkdir -p objects
      for source in *.c; do
        # shellcheck disable=SC2086 # word splitting is the pkg-config output
        $CC -c -fPIC -O2 -fvisibility=hidden -Wall -Wextra -Werror \
          $media_cflags "$source" -o "objects/''${source%.c}.o"
      done
      # shellcheck disable=SC2086
      $CC -shared objects/*.o \
        -Wl,-z,defs -Wl,-Bsymbolic -Wl,--exclude-libs,ALL \
        -o libmarkshot-media.so $media_libs -lgbm -ldl
      runHook postBuild
    '';

    installPhase = ''
            runHook preInstall
            install -Dm755 libmarkshot-media.so "$out/lib/mark-shot/media/libmarkshot-media.so"
            install -Dm644 ${ffmpeg}/share/licenses/ffmpeg-lgpl/COPYING.LGPLv2.1 \
              "$out/share/licenses/mark-shot-media/FFMPEG.txt"
            install -Dm644 ${openh264}/share/licenses/openh264/LICENSE \
              "$out/share/licenses/mark-shot-media/OPENH264.txt"
            install -Dm644 ${nv-codec-headers}/share/licenses/nv-codec-headers/README \
              "$out/share/licenses/mark-shot-media/NV-CODEC-HEADERS.txt"
            install -Dm644 ${ffmpeg}/share/mark-shot-media/FFMPEG-CONFIG.h \
              "$out/share/licenses/mark-shot-media/FFMPEG-CONFIG.h"
            install -Dm644 ${ffmpeg}/share/mark-shot-media/FFMPEG-CONFIG-COMPONENTS.h \
              "$out/share/licenses/mark-shot-media/FFMPEG-CONFIG-COMPONENTS.h"
            install -Dm644 ${ffmpeg}/share/mark-shot-media/FFMPEG-CONFIG.mak \
              "$out/share/licenses/mark-shot-media/FFMPEG-CONFIG.mak"
            cat > "$out/share/licenses/mark-shot-media/NOTICES.txt" <<'EOF'
      Mark Shot uses the FFmpeg libraries under LGPL-2.1-or-later inside one
      replaceable shared library, libmarkshot-media.so. GPL and nonfree components
      are disabled; no command-line media programs are included.

      FFmpeg 9.0.2 (LGPL-2.1-or-later; see FFMPEG.txt and FFMPEG-CONFIG.h)
      Linux software H.264: OpenH264 2.6.0 (BSD-2-Clause; see OPENH264.txt)
      NVENC headers: nv-codec-headers n13.0.19.0 (MIT; see NV-CODEC-HEADERS.txt)
      The wrapper C sources are part of mark-shot (MIT OR Apache-2.0).

      The matching sources and the exact build configuration are pinned in
      packages/mark-shot/media.nix; the upstream scripts/media/build-libraries.sh
      documents the same component set.
      EOF
            runHook postInstall
    '';

    # patchelf's fixup pass drops RPATH entries for libraries that are not
    # DT_NEEDED, but shot-media dlopens libpulse.so.0. Add the PulseAudio
    # directory back after that pass so optional audio capture keeps working,
    # while keeping the compiler runtime entries the shrink pass found needed.
    postFixup = ''
      patchelf --add-rpath "${lib.makeLibraryPath [ pkgs.libpulseaudio ]}" \
        "$out/lib/mark-shot/media/libmarkshot-media.so"
    '';

    meta = {
      description = "In-process recording and export library for mark-shot";
      homepage = "https://github.com/jswysnemc/mark-shot";
      license = with lib.licenses; [
        lgpl21Plus
        bsd2
        mit
        asl20
      ];
      platforms = lib.platforms.linux;
    };
  };
in
{
  inherit
    openh264
    nv-codec-headers
    ffmpeg
    library
    ;
}
