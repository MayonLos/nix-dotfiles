{
  pkgs,
  home,
  appearance,
  nixos,
  ...
}:
let
  inherit (pkgs) lib;
  tools = import ./tools.nix { inherit pkgs; };
  themeRoot = "PrismLauncher/themes/OneDark";
  manifest = home.xdg.dataFile."${themeRoot}/theme.json".source;
  stylesheet = home.xdg.dataFile."${themeRoot}/themeStyle.qss".source;
  sharedStylesheet = home.xdg.configFile."qt6ct/qss/one-dark.qss".source;
  catpack = home.xdg.dataFile."PrismLauncher/catpacks/NixDotfilesPrism/catpack.json".source;
  background =
    home.xdg.dataFile."PrismLauncher/catpacks/NixDotfilesPrism/prism-background.svg".source;
  iconTheme = home.xdg.dataFile."PrismLauncher/iconthemes/NixDotfilesPrism/index.theme".source;
  catIcon = home.xdg.dataFile."PrismLauncher/iconthemes/NixDotfilesPrism/cat.svg".source;
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
{
  gaming-launch =
    assert builtins.elem pkgs.proton-ge-bin nixos.programs.steam.extraCompatPackages;
    assert nixos.systemd.user.services.gaming-idle-inhibit.wantedBy == [ ];
    assert nixos.systemd.user.services.gaming-idle-inhibit.partOf == [ "gamemoded.service" ];
    assert nixos.systemd.user.services.gaming-idle-inhibit.serviceConfig.Type == "notify";
    assert nixos.programs.gamemode.settings.custom.script_timeout >= 150;
    assert nixos.programs.gamemode.settings.general.desiredgov == "ignore";
    assert nixos.programs.gamemode.settings.general.disable_splitlock == 0;
    assert nixos.programs.gamemode.settings.general.ioprio == "off";
    assert nixos.programs.gamemode.settings.gpu.apply_gpu_optimisations == "";
    assert lib.hasInfix "\${NOTIFY_SOCKET}"
      nixos.systemd.user.services.gaming-idle-inhibit.serviceConfig.ExecStart;
    assert lib.hasInfix "gaming-mode-hook start" nixos.programs.gamemode.settings.custom.start;
    assert lib.hasInfix "gaming-mode-hook end" nixos.programs.gamemode.settings.custom.end;
    assert lib.hasInfix "gaming-mode-hook end"
      nixos.systemd.user.services.gamemoded.serviceConfig.ExecStopPost;
    pkgs.runCommand "gaming-launch-check"
      { nativeBuildInputs = [ pkgs.python3 ] ++ builtins.attrValues tools; }
      ''
        python3 ${./resources}/test_gaming.py
        mkdir -p "$TMPDIR/home"
        # No bus is available here: this checks command/library discovery and
        # passthrough, while gaming-runtime checks successful registration.
        ${pkgs.coreutils}/bin/env -i PATH= HOME="$TMPDIR/home" \
          XDG_RUNTIME_DIR="$TMPDIR" GAME_RUN_GPU=integrated \
          ${tools.game-run}/bin/game-run ${pkgs.coreutils}/bin/true
        touch "$out"
      '';
  # Building the patched launcher checks the exact replacement against the
  # locked C++ source. No launcher or user configuration is run by this check.
  gaming-prism-launch = pkgs.runCommand "gaming-prism-launch-check" { } ''
    test -x ${builtins.head withoutAppearance.config.home.packages}/bin/prismlauncher
    touch "$out"
  '';
  prism-theme =
    pkgs.runCommand "prism-theme-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        MANIFEST = manifest;
        STYLESHEET = stylesheet;
        BASE_STYLESHEET = sharedStylesheet;
        PALETTE = pkgs.writeText "prism-theme-palette.json" (builtins.toJSON appearance);
        CATPACK = catpack;
        BACKGROUND = background;
        ICON_THEME = iconTheme;
        CAT_ICON = catIcon;
      }
      ''
        python3 - <<'PY'
        import json
        import os
        import pathlib
        import re
        import xml.etree.ElementTree as ET

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
        shared_qss = pathlib.Path(os.environ["BASE_STYLESHEET"]).read_text()
        assert qss.startswith(shared_qss), "Prism additions must follow the shared Qt stylesheet"
        assert not re.search(r"@[A-Z_]+@", qss), "unresolved theme token"
        images = re.findall(r"url\(([^)]+)\)", qss)
        assert images, "state indicators must include their resources"
        for image in images:
            assert pathlib.Path(image).is_file(), image
        prism_qss = qss[len(shared_qss):]
        assert "QToolBar#mainToolBar QToolButton" in prism_qss
        assert "QToolBar#instanceToolBar QToolButton" in prism_qss
        assert ":hover" in prism_qss and ":pressed" in prism_qss and ":focus" in prism_qss
        assert "QToolButton::menu-button" in prism_qss and "width: 14px" in prism_qss
        assert "QPushButton," not in prism_qss, "generic buttons must retain the shared style"
        assert "QDialogButtonBox QPushButton" in prism_qss, "only dialog footer buttons receive compact spacing"
        assert "QTabBar::tab:selected" in prism_qss and "QTabBar::tab:hover:!selected" in prism_qss
        assert "QTabWidget::pane" in prism_qss and "border-bottom-color:" in prism_qss
        assert "QGroupBox::indicator" in prism_qss and "QGroupBox::title" in prism_qss
        assert "QDoubleSpinBox::up-button" in prism_qss and "QSpinBox::down-button" in prism_qss
        catpack = json.loads(pathlib.Path(os.environ["CATPACK"]).read_text())
        assert catpack == {"name": "Nix Dotfiles Prism", "default": "prism-background.svg"}
        icon_theme = pathlib.Path(os.environ["ICON_THEME"]).read_text()
        assert "Name=One Dark Prism" in icon_theme and "Inherits=pe_colored" in icon_theme
        for svg in ("BACKGROUND", "CAT_ICON"):
            ET.parse(os.environ[svg])
            assert "@" not in pathlib.Path(os.environ[svg]).read_text(), svg
        PY
        touch "$out"
      '';
}
