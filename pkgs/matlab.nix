# MATLAB cannot be a derivation: the installer is behind a MathWorks login, so
# nothing can fetch it -- that is the caveat modules/home/programs/dev/octave.nix
# refers to. What *is* packageable is the environment it needs.
#
# MATLAB's binaries are built for an FHS distribution: they dlopen bare sonames,
# expect /usr/lib and /bin/sh to exist, and ship a bundled libstdc++ older than
# anything NixOS links against. buildFHSEnv hands them that layout; the install
# tree itself stays imperative under $HOME, where the installer can write to it.
#
# The dependency list is MathWorks' own: every entry below was checked against
# matlab-deps/r2026a/ubuntu24.04/base-dependencies.txt in
# github.com/mathworks-ref-arch/container-images (fetched 2026-09-20, 76 lines).
# The structure came from gitlab.com/doronbehar/nix-matlab, which was archived
# 2025-08-06 on a 2022-era nixpkgs pin; its list stopped at R2022b and is missing
# roughly a dozen of R2026a's libraries, so it was re-derived rather than copied.
#
# Deliberately NOT included from that list: sudo (an FHS env is not the place),
# and the RDMA/MPI/SDR set -- libibverbs, librdmacm, libpsm2, libucx, libuhd.
# Those are for Parallel Computing Toolbox across a cluster fabric and for the
# SDR hardware support package; a local parallel pool does not touch them, and
# they are a large closure to carry on the chance that it might.
#
# Nor the nine libboost-1.74 entries R2026a added. MATLAB ships its own copies
# under bin/glnxa64 with an mw prefix and its own soname
# (libmwboost_system.so.1.81.0), so nothing resolves a bare libboost soname --
# checked inside the built env, where libboost_system.so is absent and MATLAB
# starts anyway. nixpkgs' boost is 1.89 in any case, which is not what that
# list asks for.
#
# Takes `pkgs` rather than going through callPackage on purpose: targetPkgs is a
# function of the whole package set, not a handful of named inputs.
{
  pkgs,
  # Passed in rather than read from $HOME: the wrappers and the .desktop Icon=
  # both need this baked in at build time, and a build sandbox's $HOME is not
  # the user's. The home module hands over config.home.homeDirectory.
  homeDirectory,
  # Where `matlab-install` puts MATLAB and where the wrappers look for it.
  # MathWorks' own layout, so a second release can live beside this one.
  # $MATLAB_INSTALL_DIR overrides it at runtime.
  installDir ? "${homeDirectory}/.local/share/MATLAB/R2026a",
}:
let
  inherit (pkgs) lib;

  targetPkgs =
    pkgs:
    (with pkgs; [
      cacert
      alsa-lib # libasound2
      atk
      glib
      glibc
      glibcLocales
      cairo
      cups
      dbus
      fontconfig
      gdk-pixbuf
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gtk2 # still probed by the Java desktop, since R2021b
      gtk3
      nspr
      nss
      pam
      pango
      python3
      libselinux
      libsndfile
      procps
      unzip # the installer unpacks its own archives
      which
      zlib

      at-spi2-atk
      at-spi2-core
      libdrm
      libgbm # since R2024
      libglvnd # since R2022a
      libuuid # since R2022b
      libxcrypt
      libxcrypt-legacy # matlab links libcrypt.so.1, which glibc dropped
      mesa # Simulink renders through it

      gcc # mex
      gfortran # mex
      jre
      ncurses # -nodesktop
      udev

      # Without these, keyboard input silently does nothing in Simulink.
      libxkbcommon
      xkeyboard_config

      libxcb
      libxxf86vm

      # On MathWorks' R2026a list but absent from nix-matlab's, which predates
      # it. Several are new in R2024b-R2026a rather than long-standing gaps:
      # hidapi and mosquitto arrived in R2026a, libtirpc/pixman/fribidi in
      # R2024b.
      libcap
      fribidi
      hidapi # libhidapi-libusb0
      mosquitto # libmosquitto1 / libmosquittopp1
      numactl # libnuma1
      pixman
      libtirpc
      gnumake # `make`; mex shells out to it
      nettools
      wget # the network installer fetches with it

      # Not on MathWorks' list. These come from reading the CEF the installer
      # actually ships: `strings` over its bin/glnxa64/libcef.so (238 MB, CEF
      # is how both the installer UI and the Live Editor are drawn) lists the
      # sonames it dlopens, which DT_NEEDED does not cover.
      #
      # vulkan-loader is the one that matters. Since R2025a MATLAB renders
      # through WebGL over ANGLE, and ANGLE's Linux backend is Vulkan; libcef
      # dlopens libvulkan.so.1 and, failing that, falls back to the bundled
      # libvk_swiftshader.so -- software rendering that looks like MATLAB
      # merely being slow. The ICD manifests are already reachable:
      # buildFHSEnv puts /run/opengl-driver/share on XDG_DATA_DIRS, only the
      # loader was missing. pciutils is libcef's GPU probe.
      vulkan-loader
      pciutils

      # expat + freetype: MATLAB ships its own copies under bin/glnxa64 and
      # CEF resolves them first; an undefined FT_Get_Color_Glyph_Layer is how
      # that shows up. Having the current ones in the env is what makes an
      # LD_PRELOAD fix possible at all if it happens.
      expat
      freetype
      libGLU

      # Deliberately absent: libxshmfence. It is the usual Chromium GPU-fence
      # dependency, so it looks like an oversight, but this CEF build does not
      # reference it -- zero hits in libcef.so, in DT_NEEDED and in the dlopen
      # strings alike. The DRI3 sonames it does dlopen (libxcb-dri3,
      # libxcb-present, libxcb-sync) all come from libxcb, already here.

      # The X libraries. All of these were moved out of the `xorg` attribute
      # set in nixos-26.05; reaching them through xorg.* still resolves but
      # warns on every single evaluation, and this file was the only place in
      # the repo still doing it. libXfont2 keeps its capitals at the top level,
      # the rest are lowercase.
      libice # libice6, on the list since R2025
      libsm
      libx11
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxft
      libxi
      libxinerama
      libxrandr
      libxrender
      libxt
      libxtst
      libXfont2

      # libXau and the xcb-util family are transitive dependencies that resolve
      # through rpath for anything that links them normally -- but the R2026a
      # installer dlopens them by soname, and without them it dies immediately
      # after the MathWorks sign-in step rather than at startup.
      libxau
      xcbutil
      xcbutilcursor
      xcbutilimage
      xcbutilkeysyms
      xcbutilrenderutil
      xcbutilwm

      # x11-xkb-utils on MathWorks' list.
      xkbcomp
      setxkbmap
    ]);

  # Prepended to every wrapper below.
  preamble = ''
    # MATLAB bundles Qt without the wayland platform plugin, and MathWorks
    # dropped libwayland-client from the R2026a dependency list entirely -- the
    # desktop is an XWayland client and nothing else. Not conditional: Simulink
    # needs it on a Wayland session too.
    export QT_QPA_PLATFORM=xcb

    # mango does not reparent windows. Java AWT assumes a reparenting window
    # manager and paints the MATLAB desktop into a window it then loses track
    # of, which looks like a blank grey frame rather than an error.
    export _JAVA_AWT_WM_NONREPARENTING=1

    # MATLAB hardlinks from $TMPDIR into ~/.matlab to save preferences, and a
    # hardlink cannot cross a filesystem: /tmp here is a separate 16G tmpfs, so
    # the default silently loses settings between sessions. It is also RAM, and
    # the network installer streams every selected product through $TMPDIR --
    # a full product selection is 26 GB by MathWorks' own figure.
    export TMPDIR="''${TMPDIR_MATLAB:-${homeDirectory}/.cache/matlab}"
    mkdir -p "$TMPDIR"

    export MATLAB_INSTALL_DIR="''${MATLAB_INSTALL_DIR:-${installDir}}"
  '';

  # Every wrapper except matlab-install refuses to run without an install tree,
  # because MATLAB's own error for a missing one is a Java stack trace.
  requireInstall = ''
    if [ ! -x "$MATLAB_INSTALL_DIR/bin/matlab" ]; then
      echo "no MATLAB installation at $MATLAB_INSTALL_DIR" >&2
      echo "run 'matlab-install <path-to-installer-zip>' first," >&2
      echo "or point \$MATLAB_INSTALL_DIR at an existing install." >&2
      exit 1
    fi
  '';

  fhs =
    name: script:
    pkgs.buildFHSEnv {
      inherit name targetPkgs;
      runScript = pkgs.writeShellScript "${name}-runner" (preamble + script);
    };

  # LD_PRELOAD: MATLAB ships its own libstdc++ under sys/os/glnxa64 and puts it
  # ahead of everything on its internal library path. It is older than the one
  # mesa and the FHS gcc were built against, so the first OpenGL call resolves a
  # missing GLIBCXX_* symbol and the figure window dies. Forcing the FHS copy in
  # first wins that race; /lib/libstdc++.so is where it lands in this env.
  #
  # Two things nix-matlab got wrong here, both checked inside the built env:
  #
  # Its LD_LIBRARY_PATH pointed at /usr/lib/xorg/modules/dri, which buildFHSEnv
  # no longer creates. The DRI drivers are at /usr/lib/dri now and mesa finds
  # them unaided -- `glxinfo -B` in an equivalent env reports "Mesa Intel(R)
  # Graphics (RPL-S)", not llvmpipe, with nothing set. So no LIBGL_DRIVERS_PATH.
  #
  # But /run/opengl-driver/lib, where NixOS puts the NVIDIA driver, is bound
  # into the sandbox and is *not* on any library search path. The iGPU does not
  # need it; PRIME offload does. Appended, never prepended: that directory also
  # holds a libGL, and putting it first would shadow mesa's for the Intel path.
  # Set through both LDPATH_SUFFIX and LD_LIBRARY_PATH on purpose. MATLAB's
  # bin/matlab sources .matlab7rc.sh, which rebuilds LD_LIBRARY_PATH and appends
  # LDPATH_SUFFIX to it -- that is the documented hook and the one that survives.
  # LD_LIBRARY_PATH is kept for everything that does not go through that script:
  # the installer, MATLABWindow run directly to diagnose a CEF failure, mex.
  # Whether .matlab7rc.sh preserves an inherited LD_LIBRARY_PATH is not something
  # that can be checked without an install tree, so neither is assumed.
  #
  # Diagnosing a fall back to software rendering changed in R2026a: `opengl` was
  # removed as a function, and -softwareopengl is now an ignored no-op, because
  # R2025a moved rendering to WebGL-over-ANGLE inside CEF. The call is
  # `rendererinfo` -- GraphicsRenderer says SwiftShader when it has fallen back.
  matlab = fhs "matlab" (
    requireInstall
    + ''
      exec env \
        LD_PRELOAD=/lib/libstdc++.so \
        LDPATH_SUFFIX=/run/opengl-driver/lib \
        LD_LIBRARY_PATH="''${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/run/opengl-driver/lib" \
        "$MATLAB_INSTALL_DIR/bin/matlab" "$@"
    ''
  );

  matlab-install = fhs "matlab-install" ''
    src="''${1:-}"
    if [ -z "$src" ]; then
      echo "usage: matlab-install <installer .zip | extracted installer dir>" >&2
      exit 1
    fi
    # Consumed here, so the rest of "$@" reaches ./install as its own flags.
    shift

    # The download is a zip; accept it directly rather than making the caller
    # extract it, but keep working on an already-extracted tree.
    if [ -f "$src" ]; then
      tmp="$(mktemp -d)"
      # Expanded now, not at exit, so the path is fixed even if $tmp is reused.
      # shellcheck disable=SC2064
      trap "cd / && rm -rf '$tmp'" EXIT
      echo "extracting $src into $tmp ..."
      unzip -q "$src" -d "$tmp"
      src="$tmp"
    fi
    if [ ! -x "$src/install" ]; then
      echo "no 'install' executable under $src" >&2
      exit 1
    fi

    mkdir -p "$MATLAB_INSTALL_DIR"
    cat <<EOF
    ============================================================
    Destination: replace the default /usr/local/MATLAB/... , which
    is read-only on NixOS, with

        $MATLAB_INSTALL_DIR

    Sign in with a PASSWORD, not a passkey. The installer's
    embedded browser is CEF, which has no WebAuthn support, and
    choosing a passkey takes the whole installer window down
    rather than reporting anything.

    Leave the "create symlinks in /usr/local/bin" option off --
    that path is read-only here, and the wrappers replace it.

    Use the keyboard where you can. CEF under XWayland loses
    keyboard focus after a mouse click in a text field; if a
    field stops accepting input, alt-tab away and back.

    If ./install segfaults immediately: that is the known R2026a
    FLEXlm CPUID bug, which misreads the "GenuineIntel" vendor
    string as a pointer. It is reported on Arch, not confirmed on
    NixOS. Say so rather than retrying -- it needs a shim, not a
    different install directory.
    ============================================================
    EOF

    cd "$src" || exit 1
    ./install "$@"
  '';

  matlab-shell = fhs "matlab-shell" ''
    cat <<EOF
    matlab-shell: an FHS shell with MATLAB's dependencies on the library path.
    MATLAB_INSTALL_DIR=$MATLAB_INSTALL_DIR
    For running the installer by hand, or debugging a load failure with ldd.
    EOF
    exec bash "$@"
  '';

  # The language server has to run *inside* this environment, not beside it.
  # The useful half of matlab-language-server -- completion, signature help,
  # cross-file navigation, formatting -- works by launching a real MATLAB in the
  # background and asking it; launched from an ordinary NixOS process, that
  # MATLAB fails exactly the way ./install would have. Everything it can do
  # without a MATLAB (syntax errors, document symbols) would work outside, which
  # is why the failure is partial and confusing rather than obvious.
  #
  # matlab-language-server is resolved from PATH, not pinned into this closure:
  # buildFHSEnv keeps the caller's PATH, so the profile copy that
  # toolchain.nix installs is what runs, and nvim and Emacs cannot drift onto
  # two different servers.
  #
  # The flags below are the fallback, not the configuration. A client that
  # advertises workspace/configuration -- nvim does -- makes the server discard
  # every CLI argument and read its settings over LSP instead
  # (ConfigurationManager.ts:150). nixvim/plugins/lsp/servers.nix carries the
  # values that actually apply there; these are what a client without that
  # capability gets, and they are kept in step deliberately.
  #
  # Unlike matlab-shell this prints no banner. It speaks LSP over stdio, and
  # anything else written to stdout corrupts the stream.
  matlab-ls = fhs "matlab-ls" (
    requireInstall
    + ''
      if ! command -v matlab-language-server >/dev/null 2>&1; then
        echo "matlab-ls: matlab-language-server is not on PATH" >&2
        echo "add it to modules/home/programs/dev/toolchain.nix" >&2
        exit 1
      fi
      exec matlab-language-server --stdio \
        --matlabInstallPath="$MATLAB_INSTALL_DIR" \
        --matlabConnectionTiming=onStart \
        "$@"
    ''
  );

  mlint = fhs "mlint" (
    requireInstall
    + ''
      exec "$MATLAB_INSTALL_DIR/bin/glnxa64/mlint" "$@"
    ''
  );

  matlab-mex = fhs "matlab-mex" (
    requireInstall
    + ''
      exec "$MATLAB_INSTALL_DIR/bin/glnxa64/mex" "$@"
    ''
  );

  desktopItem = pkgs.makeDesktopItem {
    name = "matlab";
    desktopName = "MATLAB";
    # -desktop is required when the Exec line is not a login shell, otherwise
    # MATLAB starts headless and the launcher appears to do nothing.
    # @out@ is substituted below: a launcher does not necessarily run with the
    # Home Manager profile on PATH, the same reason octave.nix rewrites its
    # Exec line.
    exec = "@out@/bin/matlab -desktop %F";
    # An absolute path into the install tree: the only icon available is the
    # one the installer writes, and vendoring MathWorks' logo into this repo is
    # not ours to do. Resolves to nothing until MATLAB is actually installed.
    icon = "${installDir}/bin/glnxa64/cef_resources/matlab_icon.png";
    categories = [
      "Development"
      "IDE"
      "Science"
    ];
    mimeTypes = [
      "text/x-matlab"
      "text/x-octave"
    ];
    keywords = [
      "math"
      "matrix"
      "numerical"
      "simulink"
    ];
  };
in
pkgs.symlinkJoin {
  name = "matlab-fhs";
  paths = [
    matlab
    matlab-install
    matlab-shell
    matlab-ls
    mlint
    # Named matlab-mex, not mex: texlive ships a `bin/mex` of its own (the
    # Polish plain-TeX format), and two `bin/mex` in one Home Manager profile
    # is a buildEnv collision, not a shadowing.
    matlab-mex
    desktopItem
  ];
  postBuild = ''
    # symlinkJoin only symlinks the .desktop in; replace it with a real file so
    # the substitution does not write back into the desktopItem's store path.
    rm $out/share/applications/matlab.desktop
    substitute ${desktopItem}/share/applications/matlab.desktop \
      $out/share/applications/matlab.desktop \
      --replace-fail "@out@" "${placeholder "out"}"
  '';
  meta = {
    description = "FHS environment for an imperatively installed MATLAB";
    homepage = "https://www.mathworks.com/";
    # The licence of this expression, not of MATLAB.
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
