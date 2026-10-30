{ pkgs, mango }:
let
  scenefx = mango.barBlurScenefx;
  patch = ./scenefx-blur-level-clamp.patch;
  source = pkgs.applyPatches {
    name = "scenefx-blur-sampling-source";
    inherit (scenefx) src patches;
  };
in
assert builtins.elem patch scenefx.patches;
pkgs.runCommand "mango-blur-sampling"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    EGL_PLATFORM = "surfaceless";
    LIBGL_ALWAYS_SOFTWARE = "1";
    __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
  }
  ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$out"
    # Also verify the original shaders exhibit the defect: a passing regression
    # must distinguish untouched upstream code from the production patch.
    python3 ${./check-blur-edges.py} \
      --egl ${pkgs.libglvnd}/lib/libEGL.so.1 \
      --gles ${pkgs.libglvnd}/lib/libGLESv2.so.2 \
      --source ${scenefx.src} --expect-artifact > "$out/upstream.log"
    python3 ${./check-blur-edges.py} \
      --egl ${pkgs.libglvnd}/lib/libEGL.so.1 \
      --gles ${pkgs.libglvnd}/lib/libGLESv2.so.2 \
      --source ${source} > "$out/patched.log"
  ''
