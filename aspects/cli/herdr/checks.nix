{
  pkgs,
  home,
  appearance,
  ...
}:
let
  package = import ./package.nix { inherit pkgs; };
  cfg = home.xdg.configFile."herdr/config.toml".source;
in
{
  herdr-config = pkgs.runCommand "herdr-config-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    # CLI-only validation: never attach to or launch a server/session.
    ${package}/bin/herdr --version | tee version.txt
    grep -F '0.9.5' version.txt
    HERDR_CONFIG_PATH=${cfg} ${package}/bin/herdr config check
    python3 - <<'PY'
    import tomllib
    from pathlib import Path
    cfg = tomllib.loads(Path("${cfg}").read_text())
    assert cfg["theme"]["custom"]["accent"] == "${appearance.blue}"
    assert cfg["theme"]["custom"]["active_row_bg"] == "${appearance.selection}"
    assert cfg["ui"]["tab_bar_position"] == "bottom"
    assert cfg["onboarding"] is False
    assert "herdr-terminal" in "${home.xdg.desktopEntries.herdr.exec}"
    assert "${toString home.xdg.desktopEntries.herdr.terminal}" == ""
    assert "SUPER+ALT,H,spawn,herdr-terminal" in Path("${
      home.xdg.configFile."mango/config.conf".source
    }").read_text()
    PY
    mkdir "$out"
    cp version.txt "$out/"
    cp ${cfg} "$out/config.toml"
  '';
}
