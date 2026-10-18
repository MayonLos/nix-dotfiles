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
  # itself, so Home Manager cannot own it. The activation below points it at a
  # dispatcher that selects the Mango or Hyprland detector from session markers.
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
      install -Dm755 ${./resources/window-detection-mango} \
        "$out/bin/mark-shot-window-detection-mango"
      install -Dm755 ${./resources/window-detection-wayland} \
        "$out/bin/mark-shot-window-detection-wayland"
      substituteInPlace "$out/bin/mark-shot-window-detection-mango" \
        --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
      substituteInPlace "$out/bin/mark-shot-window-detection-wayland" \
        --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
    '';
    inherit (mark-shot-unpatched) meta;
  };

  screenshotScreen = pkgs.writeShellScriptBin "screenshot-screen" ''
    set -euo pipefail
    img="$(${pkgs.coreutils}/bin/mktemp --suffix=.png)"
    trap '${pkgs.coreutils}/bin/rm -f "$img"' EXIT

    session="$(${mark-shot}/bin/mark-shot-window-detection-wayland --session)"
    case "$session" in
      hyprland)
        # `monitors -j` exposes the focused output. Hyprland has no screenshot
        # IPC; grim captures through wlr-screencopy.
        output="$(${pkgs.hyprland}/bin/hyprctl -j monitors | ${pkgs.jq}/bin/jq -er '[.[] | select(.focused == true) | .name] | if length == 1 then .[0] else error("expected one focused Hyprland monitor") end')"
        ;;
      mango)
        output="$(${config.wayland.windowManager.mango.package}/bin/mmsg get cursorpos | ${pkgs.jq}/bin/jq -er '.monitor')"
        ;;
      *)
        echo "screenshot-screen: unsupported or unidentified Wayland session" >&2
        exit 1
        ;;
    esac
    ${pkgs.grim}/bin/grim -o "$output" "$img"
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png <"$img" >/dev/null 2>&1
    ${pkgs.libnotify}/bin/notify-send "截图已复制" "当前屏幕：$output" || true
  '';

  # Both compositor configurations use these Print-family OCR entry points.
  # The full-screen variant captures every output; the region variant permits
  # cancellation without an error. Tools are store-qualified, and the adjacent
  # Tesseract recipe includes both English and simplified Chinese data.
  tesseractOcr = pkgs.callPackage ./tesseract-ocr.nix { };

  mkOcr =
    name: screen:
    pkgs.writeShellScriptBin name ''
      set -euo pipefail

      # mango spawns children without a login shell, so LANG may be unset and
      # coreutils would fall back to a byte-oriented C locale -- `cut -c` below
      # would then split a multi-byte Chinese character in the notification
      # preview. C.UTF-8 is built by aspects/system/maintenance/locale.nix.
      export LC_ALL=C.UTF-8

      img="$(${pkgs.coreutils}/bin/mktemp --suffix=.png)"
      trap '${pkgs.coreutils}/bin/rm -f "$img"' EXIT

      ${
        if screen then
          ''${pkgs.grim}/bin/grim "$img"''
        else
          ''
            # Cancelling slurp is the user changing their mind, not a failure:
            # leave without a notification.
            geom="$(${pkgs.slurp}/bin/slurp)" || exit 0
            ${pkgs.grim}/bin/grim -g "$geom" "$img"
          ''
      }

      if ! text="$(${tesseractOcr}/bin/tesseract "$img" - -l eng+chi_sim --psm 6 2>/dev/null)" \
        || [ -z "$text" ]; then
        ${pkgs.libnotify}/bin/notify-send "OCR" "没有识别到文字" || true
        exit 1
      fi

      # wl-copy forks a long-lived child that keeps serving the selection, and
      # that child inherits this script's stdout/stderr. Without the redirect
      # the pipe stays open after the script exits, so any caller that reads our
      # output (`ocr-screen | head`, a wrapper, a test) waits forever. Measured:
      # a captured run hung until it was killed while the OCR itself had already
      # succeeded and the clipboard was already set.
      printf '%s' "$text" | ${pkgs.wl-clipboard}/bin/wl-copy >/dev/null 2>&1
      preview="$(printf '%s' "$text" | ${pkgs.coreutils}/bin/tr '\n' ' ' | ${pkgs.coreutils}/bin/cut -c1-120)"
      ${pkgs.libnotify}/bin/notify-send "OCR 已复制" "$preview" || true
    '';
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
    screenshotScreen
    inputs.wayscrollshot.packages.${system}.default
    (mkOcr "ocr-region" false)
    (mkOcr "ocr-screen" true)
  ];

  # Rewrite only windowDetection.command, leaving every other key mark-shot
  # stores in that file alone. The dispatcher chooses one of the two explicitly
  # supported sessions at runtime, since this file is shared between them.
  home.activation.markShotWindowDetection = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="${config.xdg.configHome}/mark-shot/config.json"
    want="mark-shot-window-detection-wayland"
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
