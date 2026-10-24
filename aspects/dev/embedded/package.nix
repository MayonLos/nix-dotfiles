# ST's installer requires a browser download. Pin the official Linux archive;
# do not use the old 2.5.0 installer bundled with the board's teaching material.
# Packaging reference: https://github.com/NixOS/nixpkgs/issues/355181
{ pkgs }:
let
  inherit (pkgs) lib;
  version = "2.23.0";
  installerEnv = pkgs.buildFHSEnv {
    name = "stm32cubeprogrammer-installer-env";
    targetPkgs = p: [
      p.jdk17
      p.coreutils
      p.bash
    ];
    runScript = "java";
  };
  payload = pkgs.stdenvNoCC.mkDerivation {
    pname = "stm32cubeprogrammer-unwrapped";
    inherit version;
    src = pkgs.requireFile {
      name = "SetupSTM32CubeProgrammer_linux_64.zip";
      sha256 = "0aj4cxhzqnf0imb44bpv340vsv1fvimvd6qz4jrmxi28l2jn17ka";
      url = "https://www.st.com/en/development-tools/stm32cubeprog.html";
      message = ''
        Download STM32CubeProgrammer ${version} for Linux x86_64 from ST.
        Rename the ZIP to SetupSTM32CubeProgrammer_linux_64.zip, then run:
          nix-store --add-fixed sha256 /path/to/SetupSTM32CubeProgrammer_linux_64.zip
        The archive is pinned by SHA-256; a different version will not match.
      '';
    };
    nativeBuildInputs = [
      pkgs.unzip
      pkgs.jdk17
      pkgs.icoutils
    ];
    dontUnpack = true;
    dontBuild = true;
    # The installed binaries and bundled JRE run inside the FHS environment
    # below. Patching their embedded paths would break ST's library discovery.
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      unzip -q "$src" "SetupSTM32CubeProgrammer-${version}.exe" 'jre/*'
      mkdir -p "$TMPDIR/installer-home"
      ${installerEnv}/bin/stm32cubeprogrammer-installer-env -Djava.awt.headless=true -Duser.home="$TMPDIR/installer-home" -DINSTALL_PATH="$PWD/installed" \
        -jar "SetupSTM32CubeProgrammer-${version}.exe" -options-system
      test -f installed/bin/STM32_Programmer_CLI
      test -f installed/bin/STM32CubeProgrammerLauncher
      mkdir -p "$out"
      cp -a installed/. "$out/"
      test -x "$out/bin/jre/bin/java"

      # ST's launcher has an executable prefix which some JVMs reject as a
      # corrupt JAR. Repack its Java contents while retaining the manifest.
      mkdir launcher-jar
      (cd launcher-jar
        jar -xf "$out/bin/STM32CubeProgrammerLauncher"
        jar -cfm "$out/bin/STM32CubeProgrammerLauncher" META-INF/MANIFEST.MF .
      )
      mkdir -p icons "$out/share/icons/hicolor/256x256/apps"
      icotool -x -w 256 -h 256 -o icons "$out/util/Programmer.ico"
      icon=$(find icons -name '*.png' -print -quit)
      test -n "$icon"
      cp "$icon" "$out/share/icons/hicolor/256x256/apps/stm32cubeprogrammer.png"
      runHook postInstall
    '';
  };
  desktopItem = pkgs.makeDesktopItem {
    name = "stm32cubeprogrammer";
    desktopName = "STM32CubeProgrammer";
    comment = "Program STM32 devices over USB DFU, UART or ST-LINK";
    exec = "stm32cubeprogrammer";
    icon = "stm32cubeprogrammer";
    categories = [ "Development" ];
  };
in
pkgs.buildFHSEnv {
  pname = "stm32cubeprogrammer";
  inherit version;
  targetPkgs =
    p: with p; [
      libusb1
      stdenv.cc.cc.lib
      zlib
      zstd
      brotli
      glib
      libkrb5
      openssl
      pcsclite
      gtk3
      fontconfig
      freetype
      alsa-lib
      libx11
      libxext
      libxi
      libxrender
      libxtst
      libxrandr
      libxcursor
      libxinerama
      libxfixes
      libxcomposite
      libxdamage
      libxxf86vm
      libxcb
      libxkbcommon
      libGL
      qt6Packages.qtbase
      qt6Packages.qtserialport
      qt6Packages.qtwayland
      cacert
    ];
  runScript = pkgs.writeShellScript "stm32cubeprogrammer-run" ''
    set -eu
    cd ${payload}/bin
    if [ "''${1:-}" = --cli ]; then
      shift
      exec ./STM32_Programmer_CLI "$@"
    fi
    # Avoid mixing desktop Qt plugins with ST's bundled toolkit.
    unset QT_PLUGIN_PATH QML2_IMPORT_PATH QT_QPA_PLATFORMTHEME
    export QT_QPA_PLATFORM=xcb
    # ST's JavaFX 8 UI uses X11; GTK must not select the Wayland backend.
    export GDK_BACKEND=x11
    export _JAVA_AWT_WM_NONREPARENTING=1
    exec ./jre/bin/java -jar ./STM32CubeProgrammerLauncher "$@"
  '';
  extraInstallCommands = ''
    cat > "$out/bin/STM32_Programmer_CLI" <<EOF
    #!${pkgs.runtimeShell}
    exec "$out/bin/stm32cubeprogrammer" --cli "\$@"
    EOF
    chmod +x "$out/bin/STM32_Programmer_CLI"
    ln -s stm32cubeprogrammer "$out/bin/STM32CubeProgrammer"
    mkdir -p "$out/share"
    ln -s ${desktopItem}/share/applications "$out/share/applications"
    ln -s ${payload}/share/icons "$out/share/icons"
  '';
  passthru.unwrapped = payload;
  meta = {
    description = "ST's STM32 programming tool with GUI and CLI";
    homepage = "https://www.st.com/en/development-tools/stm32cubeprog.html";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "stm32cubeprogrammer";
  };
}
