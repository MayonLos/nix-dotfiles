{
  pkgs,
  home,
  appearance,
  ...
}:
let
  inherit (pkgs) lib;
  themeRoot = "PrismLauncher/themes/OneDark";
  manifest = home.xdg.dataFile."${themeRoot}/theme.json".source;
  stylesheet = home.xdg.dataFile."${themeRoot}/themeStyle.qss".source;
  # Gaming remains usable without the optional appearance input. Exercise
  # the actual module rather than duplicating its conditional expression.
  withoutAppearance = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      {
        options.home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        options.xdg.dataFile = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
        };
      }
      (import ./prismlauncher.nix { palette = null; })
    ];
  };
in
assert withoutAppearance.config.xdg.dataFile == { };
assert builtins.length withoutAppearance.config.home.packages == 1;
assert stylesheet == home.xdg.configFile."qt6ct/qss/one-dark.qss".source;
{
  prism-theme =
    pkgs.runCommand "prism-theme-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        MANIFEST = manifest;
        STYLESHEET = stylesheet;
        PALETTE = pkgs.writeText "prism-theme-palette.json" (builtins.toJSON appearance);
      }
      ''
        python3 - <<'PY'
        import json
        import os
        import pathlib
        import re

        theme = json.loads(pathlib.Path(os.environ["MANIFEST"]).read_text())
        palette = json.loads(pathlib.Path(os.environ["PALETTE"]).read_text())
        assert theme["name"] == "One Dark"
        assert theme["widgets"] == "Fusion"
        assert theme["qssFilePath"] == "themeStyle.qss"
        assert 0 < theme["colors"]["fadeAmount"] < 1
        assert theme["colors"]["fadeColor"] == palette["bg"]
        # Prism's instance view reads QPalette directly: QSS alone cannot fix
        # its background or selection inherited from the builtin Dark theme.
        for role, key in {
            "Window": "bg", "WindowText": "brightFg", "Base": "deep",
            "AlternateBase": "surface", "Text": "brightFg",
            "Button": "surface", "ButtonText": "brightFg",
            "Highlight": "selection", "HighlightedText": "brightFg",
            "ToolTipBase": "surface", "ToolTipText": "brightFg", "Link": "blue",
        }.items():
            assert theme["colors"][role] == palette[key], role
        qss = pathlib.Path(os.environ["STYLESHEET"]).read_text()
        assert not re.search(r"@[A-Z_]+@", qss), "unresolved theme token"
        images = re.findall(r"url\(([^)]+)\)", qss)
        assert images, "state indicators must include their resources"
        for image in images:
            assert pathlib.Path(image).is_file(), image
        PY
        touch "$out"
      '';
}
