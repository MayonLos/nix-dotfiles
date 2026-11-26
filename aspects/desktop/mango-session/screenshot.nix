{ pkgs, ... }:

let
  # Region, annotation and scrolling capture come from the upstream mark-shot
  # source plus this repository's patches in packages/mark-shot. It asks mmsg
  # for window rectangles itself.
  mark-shot = pkgs.local.mark-shot;

  # Print-family OCR entry points used by mango.nix. Region cancellation is
  # harmless; the full-screen variant captures every output. All tools use
  # store paths and the adjacent Tesseract recipe adds simplified Chinese.
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
  # Region select, annotate, copy, save, pin and scrolling capture are one
  # program. Ctrl+Print is Noctalia's full-screen screenshot, Shift+Print runs
  # `mark-shot --scroll`. grim/slurp stay as the OCR capture backend.
  home.packages = [
    mark-shot
    (mkOcr "ocr-region" false)
    (mkOcr "ocr-screen" true)
  ];
}
