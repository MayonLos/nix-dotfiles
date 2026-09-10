{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # Mango exposes every arranged client rectangle through its IPC, including
  # tiled windows and the space reserved by layer-shell panels. The replacement
  # therefore only filters and clips those rectangles; see the header comment
  # in _mark-shot/window-detection-mango.
  #
  # Upstream ships detectors for gnome, hyprland, kde and niri and none for
  # mango, so this one is added rather than replacing a file of the same name.
  # mark-shot resolves windowDetection.command through PATH, but that command
  # is recorded in ~/.config/mark-shot/config.json -- a file mark-shot rewrites
  # itself, so Home Manager cannot own it. It still says
  # `mark-shot-window-detection-niri` on a machine that came from the niri
  # branch, which under mango would silently run upstream's niri script and
  # get nothing back. The activation below repoints it.
  #
  # symlinkJoin rather than overrideAttrs, because overrideAttrs folds the script
  # into the main derivation and every edit to it would then recompile the whole
  # Qt application. Here a script change rebuilds one trivial symlink farm.
  mark-shot-unpatched = inputs.mark-shot.packages.${system}.default;

  mark-shot = pkgs.symlinkJoin {
    name = "mark-shot-${mark-shot-unpatched.version}";
    paths = [ mark-shot-unpatched ];
    postBuild = ''
      rm -f "$out/bin/mark-shot-window-detection-mango"
      install -Dm755 ${./_mark-shot/window-detection-mango} \
        "$out/bin/mark-shot-window-detection-mango"
      substituteInPlace "$out/bin/mark-shot-window-detection-mango" \
        --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
    '';
    inherit (mark-shot-unpatched) meta;
  };
in
{
  # Replaces the hand-rolled `slurp -d | grim -g | satty` pipeline.
  #
  # mark-shot does region select, annotate, copy, save and pin-to-desktop in one
  # program, and its README states it targets Wayland compositors. It
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

  # Rewrite only windowDetection.command, leaving every other key mark-shot
  # stores in that file alone. Idempotent, and a no-op once it already points
  # at the mango helper.
  home.activation.markShotWindowDetection = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="${config.xdg.configHome}/mark-shot/config.json"
    want="mark-shot-window-detection-mango"
    if [ -r "$target" ] \
      && ! ${lib.getExe pkgs.jq} -e --arg w "$want" \
             '.windowDetection.command == $w' "$target" >/dev/null; then
      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      if ${lib.getExe pkgs.jq} --arg w "$want" \
           '.windowDetection.command = $w' "$target" > "$tmp"; then
        run ${pkgs.coreutils}/bin/install -m 0644 "$tmp" "$target"
      fi
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    fi
  '';
}
