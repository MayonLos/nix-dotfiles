{
  pkgs,
  home,
  nixos,
  ...
}:
let
  inherit (pkgs) lib;
  prism = lib.findFirst (
    package: (package.pname or "") == "prismlauncher"
  ) (throw "gaming runtime check needs the selected Prism package") home.home.packages;
  # Substitute only the application binary, keeping the selected package's
  # actual Qt/LD_LIBRARY_PATH wrapper recipe and all its override arguments.
  probe = lib.makeOverridable (
    _:
    pkgs.runCommand "prism-runtime-probe-unwrapped" { inherit (prism) version meta; } ''
      mkdir -p "$out/bin"
      # wrapQtAppsHook only wraps ELF executables; a shell-script substitute
      # would silently skip the production library-search-path wrapper.
      cp ${pkgs.bash}/bin/bash "$out/bin/prismlauncher"
    ''
  ) { };
  prismProbe = prism.override { prismlauncher-unwrapped = probe; };
  lwjglSdl = pkgs.fetchurl {
    url = "https://repo.maven.apache.org/maven2/org/lwjgl/lwjgl-sdl/3.4.0/lwjgl-sdl-3.4.0-natives-linux.jar";
    hash = "sha256-qZ72P2WWosVWra0zCbj0Nawnj/IPfXi2jXrBZfNZ8NY=";
  };
in
{
  gaming-runtime = import ./runtime-vm.nix {
    inherit pkgs;
    steamRun = nixos.programs.steam.package.run;
  };
  gaming-sdl3-wayland =
    pkgs.runCommand "gaming-sdl3-wayland-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.unzip
          pkgs.sway-unwrapped
        ];
      }
      ''
            unzip -p ${lwjglSdl} linux/x64/org/lwjgl/sdl/libSDL3.so > libSDL3.so
            export SDL3_LIBRARY="$PWD/libSDL3.so"
        python3 ${./resources/test_headless.py} ${prismProbe}/bin/prismlauncher \
          -c 'exec ${pkgs.python3}/bin/python3 ${./resources/test_sdl_wayland.py}'
            touch "$out"
      '';
}
