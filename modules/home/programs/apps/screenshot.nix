{
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # Upstream's niri window-detection script only knows waybar and
  # DankMaterialShell panels, so with a noctalia bar it reserves nothing at the
  # top of the work area, and it also starts the first tile of a column flush
  # with the work area instead of one `gaps` below it. Every hover rectangle
  # landed ~42 logical px too high: the bottom of a window fell outside the box
  # and a strip of the bar above it was swallowed. The replacement measures the
  # bar's exclusive zone from the tallest column and mirrors niri's own layout
  # code; see the header comment in _mark-shot/window-detection-niri.
  #
  # It replaces the file cmake installed under the same name: mark-shot resolves
  # the command through PATH, so windowDetection.command in
  # ~/.config/mark-shot/config.json keeps pointing at the stock name.
  #
  # symlinkJoin rather than overrideAttrs, because overrideAttrs folds the script
  # into the main derivation and every edit to it would then recompile the whole
  # Qt application. Here a script change rebuilds one trivial symlink farm.
  mark-shot-unpatched = inputs.mark-shot.packages.${system}.default;

  mark-shot = pkgs.symlinkJoin {
    name = "mark-shot-${mark-shot-unpatched.version}";
    paths = [ mark-shot-unpatched ];
    postBuild = ''
      rm -f "$out/bin/mark-shot-window-detection-niri"
      install -Dm755 ${./_mark-shot/window-detection-niri} \
        "$out/bin/mark-shot-window-detection-niri"
      substituteInPlace "$out/bin/mark-shot-window-detection-niri" \
        --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
    '';
    inherit (mark-shot-unpatched) meta;
  };
in
{
  # Replaces the hand-rolled `slurp -d | grim -g | satty` pipeline.
  #
  # mark-shot does region select, annotate, copy, save and pin-to-desktop in one
  # program, and its README states it targets Wayland compositors like niri. It
  # still calls grim and wl-clipboard internally, so those packages stay; satty
  # had no other user and is gone from packages.nix.
  #
  # wayscrollshot does scrolling capture (scroll and stitch) for long web pages
  # and long chat logs -- something the old pipeline could not do at all. It
  # needs slurp and grim at runtime.
  home.packages = [
    mark-shot
    inputs.wayscrollshot.packages.${system}.default
  ];
}
