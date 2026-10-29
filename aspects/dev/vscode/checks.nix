{
  pkgs,
  home,
  appearance,
  ...
}:
let
  defaults = pkgs.writeText "vscode-defaults.json" (
    builtins.toJSON (import ./settings.nix { palette = appearance; })
  );
in
{
  vscode-settings =
    assert home.programs.vscode.profiles.default.userSettings == { };
    assert builtins.any (
      extension: extension.vscodeExtUniqueId == "zhuangtongfa.material-theme"
    ) home.programs.vscode.profiles.default.extensions;
    assert !(builtins.hasAttr "Code/User/settings.json" home.xdg.configFile);
    pkgs.runCommand "vscode-settings-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      cp ${./seed-settings.py} seed-settings.py
      cp ${./test-seed.py} test-seed.py
      python3 test-seed.py ${defaults}
      python3 - <<'PY'
      import json
      from pathlib import Path
      cfg = json.loads(Path('${defaults}').read_text())
      colors = cfg['workbench.colorCustomizations']
      assert colors['statusBar.background'] == '${appearance.bg}'
      assert colors['statusBar.noFolderBackground'] == '${appearance.bg}'
      assert colors['statusBar.debuggingBackground'] == '${appearance.orange}'
      assert colors['editor.background'] == '${appearance.deep}'
      assert colors['tab.activeBorderTop'] == '${appearance.blue}'
      assert colors['sideBar.border'] == colors['panel.border'] == '${appearance.border}'
      assert cfg['workbench.colorTheme'] == 'One Dark Pro'
      assert '${appearance.fonts.mono}' in cfg['editor.fontFamily']
      assert cfg['editor.minimap.enabled'] is False
      assert cfg['workbench.startupEditor'] == 'none'
      assert cfg['extensions.ignoreRecommendations'] is True
      PY
      cp ${defaults} "$out"
    '';
}
