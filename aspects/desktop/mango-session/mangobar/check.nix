{
  pkgs,
  home,
  palette,
}:
let
  python = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.pillow
    pythonPackages.pygobject3
  ]);
  # The menu uses the bar font. Fontconfig must resolve the same family the
  # stylesheet names, otherwise mangobar falls back to a different face and the
  # ink metrics in this test stop matching production.
  fontconfig = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.maple-mono.NF-CN
      pkgs.dejavu_fonts
    ];
    impureFontDirectories = [ ];
  };
  vptr = pkgs.callPackage ./vptr.nix { };
  paletteJson = pkgs.writeText "onedark-mangobar-tray-palette.json" (
    builtins.toJSON {
      inherit (palette)
        surface
        selection
        border
        brightFg
        muted
        ;
    }
  );
in
# Renders the real patched mangobar package and the real generated stylesheet
# in a private headless sway at 2560x1600/1.5, with two real StatusNotifierItem
# + DBusMenu services on a private session bus, then sends genuine pointer
# events through a virtual pointer and checks the screenshots.
pkgs.runCommand "mangobar-tray-pixels"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    export FONTCONFIG_FILE=${fontconfig}
    # dbus-run-session execs dbus-daemon by name, and the build PATH has no
    # dbus in it.
    export PATH=${pkgs.dbus}/bin:$PATH
    mkdir -p "$out/config" "$out/screens" "$out/logs"
    cp ${home.xdg.configFile."mangobar/config.jsonc".source} "$out/config/config.jsonc"
    cp ${home.xdg.configFile."mangobar/style.css".source} "$out/config/style.css"
    # The build sandbox has no /etc/dbus-1/session.conf; point dbus at the
    # config shipped by its own package instead of the host file.
    ${pkgs.dbus}/bin/dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
      python3 ${./check-tray-menu.py} \
        --mangobar ${home.services.mangobar.package}/bin/mangobar \
        --sway ${pkgs.sway-unwrapped}/bin/sway \
        --grim ${pkgs.grim}/bin/grim \
        --python ${python}/bin/python3 \
        --vptr ${vptr}/bin/vptr \
        --provider ${./provider.py} \
        --config-dir "$out/config" \
        --palette ${paletteJson} \
        --out "$out" \
        --mode assert
  ''
