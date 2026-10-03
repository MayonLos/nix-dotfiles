{ lib, pkgs, ... }:

let
  firefoxScripts = ./_firefox;
  firefoxChrome = pkgs.writeText "firefox-userChrome-fallback.css" (
    builtins.replaceStrings
      [
        "{{ colors.surface.default.hex }}"
        "{{ colors.surface_container_lowest.default.hex }}"
        "{{ colors.surface_container_high.default.hex }}"
        "{{ colors.on_surface.default.hex }}"
        "{{ colors.on_surface_variant.default.hex }}"
        "{{ colors.primary.default.hex }}"
        "{{ colors.tertiary.default.hex }}"
        "{{ colors.secondary.default.hex }}"
      ]
      [
        "#1a1b26"
        "#16161e"
        "#292e42"
        "#c0caf5"
        "#565f89"
        "#7aa2f7"
        "#7dcfff"
        "#bb9af7"
      ]
      (builtins.readFile ./_firefox/noctalia-userChrome.css)
  );
in
{
  home.activation.seedFirefoxProfileUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 ${firefoxScripts}/seed-firefox-ui.py ${firefoxChrome}
  '';
}
