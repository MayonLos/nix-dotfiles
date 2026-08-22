{ pkgs, lib, ... }:
let
  # In nixpkgs' JetBrains 2026.2 packages, autoPatchelf leaves the RPATH of
  # lib/skiko-awt-runtime-all/libskiko-linux-x64.so pointing at the build
  # directory (/build/...), so libGL/libX11/libfontconfig/libstdc++ cannot be
  # resolved at runtime. The Compose renderer then fails to load and the welcome
  # screen spins forever with clicks doing nothing. Upstream's extraLdPath
  # argument goes through extendMkDerivation and cannot be reached via
  # overrideAttrs, hence this outer wrapper adding those libs to
  # LD_LIBRARY_PATH.
  skikoLibs = with pkgs; [
    libGL
    libx11
    fontconfig
    stdenv.cc.cc.lib
  ];

  fixSkiko =
    ide:
    pkgs.symlinkJoin {
      name = "${ide.pname}-${ide.version}-skiko-fix";
      paths = [ ide ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        # With a single input buildEnv symlinks $out/bin straight at the original
        # package; expand it into a real directory first.
        if [ -L "$out/bin" ]; then
          target=$(readlink -f "$out/bin")
          rm "$out/bin"
          mkdir "$out/bin"
          ln -s "$target"/* "$out/bin/"
        fi
        wrapProgram "$out/bin/${ide.meta.mainProgram}" \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath skikoLibs}"
      '';
      inherit (ide) meta;
    };
in
{
  home.packages = map fixSkiko (
    with pkgs.jetbrains;
    [
      idea
      pycharm
      clion
      webstorm
      datagrip
      rust-rover
    ]
  );
}
