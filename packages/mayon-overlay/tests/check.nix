{
  pkgs,
  # Pass the Mango package to exercise the second compositor scenario. Without
  # it the check runs the Sway scenario only. From this repository:
  #   mango = inputs.mango.packages.${system}.mango;
  mango ? null,
}:
let
  overlay = import ../. { inherit pkgs; };
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  mangoArgs = if mango == null then "" else "--mango ${mango}/bin/mango";
in
pkgs.runCommand "mayon-overlay-headless-check"
  {
    nativeBuildInputs = [ python ];
  }
  ''
    # The script creates a private HOME/XDG_RUNTIME_DIR under --out and starts
    # headless Sway (pixman renderer) and optionally Mango. It never touches the
    # invoking user's session.
    python3 ${./headless_check.py} \
      --overlay-bin ${overlay}/bin/mayon-overlay \
      --overlay-unwrapped ${overlay}/bin/.mayon-overlay-wrapped \
      --sway ${pkgs.sway-unwrapped}/bin/sway \
      ${mangoArgs} \
      --grim ${pkgs.grim}/bin/grim \
      --wl-copy ${pkgs.wl-clipboard}/bin/wl-copy \
      --wl-paste ${pkgs.wl-clipboard}/bin/wl-paste \
      --cliphist ${pkgs.cliphist}/bin/cliphist \
      --wtype ${pkgs.wtype}/bin/wtype \
      --wev ${pkgs.wev}/bin/wev \
      --wayland-info ${pkgs.wayland-utils}/bin/wayland-info \
      --glib ${pkgs.glib.bin}/bin/gio \
      --fontconfig ${pkgs.fontconfig}/bin/fc-match \
      --coreutils ${pkgs.coreutils}/bin \
      --shell ${pkgs.runtimeShell} \
      --font ${pkgs.inter}/share/fonts/truetype/InterVariable.ttf \
      --font-fallback ${pkgs.maple-mono.NF-CN}/share/fonts/truetype/MapleMono-NF-CN-Regular.ttf \
      --out "$out"
  ''
