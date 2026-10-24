{
  pkgs,
  home,
  host,
  palette,
}:
assert home.wayland.windowManager.mango.package == host.programs.mango.package;
pkgs.runCommand "mango-focused-shadow-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  test -x ${host.programs.mango.package}/bin/mango
  python3 - <<'PY'
  from pathlib import Path
  cfg = Path("${home.xdg.configFile."mango/config.conf".source}").read_text()
  def color(value, alpha="ff"):
      return "0x" + value.removeprefix("#") + alpha
  for field, value in {
      "border_px": "2",
      "focus_color": color("${palette.blue}"),
      "scratchpad_color": color("${palette.blue}"),
      "global_color": color("${palette.blue}"),
      "overlay_color": color("${palette.blue}"),
      "border_color": color("${palette.surface}"),
      "focused_shadows_color": color("${palette.blue}", "38"),
      "shadows_color": color("${palette.black}", "52"),
      "shadow_only_floating": "0",
      "tab_bar_decorate_font_desc": "${palette.fonts.mono} 10.5",
      "title_message_bar_decorate_font_desc": "${palette.fonts.mono} 10.5",
  }.items():
      assert f"{field}={value}" in cfg.replace(" = ", "="), (field, value)
  PY
  touch "$out"
''
