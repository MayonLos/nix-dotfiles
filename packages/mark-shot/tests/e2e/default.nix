{
  pkgs,
  markShot,
  mango ? null,
}:
let
  # Every tool the private harness shells out to. `file` and ImageMagick are
  # used for magic/CRC/pixel assertions; dbus and swaybg build the isolated
  # session; wl-clip-persist is the live-session clipboard owner that exposed
  # the truncated-transfer bug.
  tools = with pkgs; [
    python3
    grim
    wl-clipboard
    wl-clip-persist
    imagemagick
    swaybg
    wtype
    dbus
    file
    coreutils
    gnugrep
  ];
in
pkgs.writeShellApplication {
  name = "mark-shot-e2e";
  runtimeInputs = tools;
  text = ''
    export MARK_SHOT="${markShot}/bin/mark-shot"
    export MS_E2E_GRIM="${pkgs.grim}/bin/grim"
    export MS_E2E_WL_PASTE="${pkgs.wl-clipboard}/bin/wl-paste"
    export MS_E2E_WL_COPY="${pkgs.wl-clipboard}/bin/wl-copy"
    export MS_E2E_CLIP_PERSIST="${pkgs.wl-clip-persist}/bin/wl-clip-persist"
    export MS_E2E_MAGICK="${pkgs.imagemagick}/bin/magick"
    export MS_E2E_FILE="${pkgs.file}/bin/file"
    export MS_E2E_SWAYBG="${pkgs.swaybg}/bin/swaybg"
    export MS_E2E_WTYPE="${pkgs.wtype}/bin/wtype"
    export MS_E2E_DBUS="${pkgs.dbus}/bin/dbus-run-session"
    export MS_E2E_PYTHON="${pkgs.python3}/bin/python3"
    export MS_E2E_UPSTREAM_SCRIPTS="${../..}/scripts"
    ${pkgs.lib.optionalString (mango != null) ''
      export MS_E2E_MANGO="${mango}/bin/mango"
    ''}
    exec ${pkgs.python3}/bin/python3 ${./run.py} "$@"
  '';
}
