{
  pkgs,
  home,
  host,
}:
let
  inherit (pkgs) lib;
  baseConfig = home.xdg.configFile."noctalia/config.toml".source;
  configFile = home.xdg.configFile."hypr/hyprland.lua".source;
  shellConfig = home.xdg.configFile."noctalia-sessions/hyprland.toml".source;
  targets = home.nixDotfiles.desktopSessionTargets;
in
assert home.wayland.windowManager.hyprland.enable;
assert host.programs.hyprland.enable;
assert host.programs.hyprland.package != null;
assert
  lib.sort builtins.lessThan targets == [
    "hyprland-session.target"
    "mango-session.target"
  ];
assert host.services.displayManager.noctalia-greeter.settings.session.default == "Mango";
assert host.xdg.portal.config.hyprland."org.freedesktop.impl.portal.ScreenCast" == "hyprland";
assert builtins.all (
  target:
  builtins.elem "pipewire.socket"
    home.systemd.user.targets.${lib.removeSuffix ".target" target}.Unit.Wants
) targets;
pkgs.runCommand "hyprland-session-checks"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.python3
    ];
  }
  ''
    mkdir -p "$out"
    desktop="${host.programs.hyprland.package}/share/wayland-sessions/hyprland.desktop"
    test -f "$desktop"
    exec_line=$(sed -n 's/^Exec=//p' "$desktop")
    test -n "$exec_line"
    wrapper_exe=''${exec_line%% *}
    launcher=''${exec_line#* }
    test "$wrapper_exe" != "$exec_line"
    case "$wrapper_exe" in */bin/hyprland-session) ;; *) echo "unexpected Hyprland session Exec: $exec_line" >&2; exit 1 ;; esac
    case "$launcher" in */bin/start-hyprland) ;; *) echo "unexpected Hyprland launcher: $launcher" >&2; exit 1 ;; esac
    test -x "$wrapper_exe"
    test -x "$launcher"

    python3 ${./resources}/test_hyprland_session.py \
      ${pkgs.bash}/bin/bash ${./resources}/hyprland-session > "$TMPDIR/runtime-tests.log" 2>&1 \
      || { cat "$TMPDIR/runtime-tests.log"; exit 1; }
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_STATE_HOME="$TMPDIR/state" XDG_CACHE_HOME="$TMPDIR/cache" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME/noctalia" "$XDG_CONFIG_HOME/noctalia-sessions" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR" "$out"
    chmod 700 "$XDG_RUNTIME_DIR"
    unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
    ${lib.getExe home.wayland.windowManager.hyprland.finalPackage} --verify-config --config ${configFile} > "$out/hyprland.log" 2>&1 || { cat "$out/hyprland.log"; exit 1; }
    ${lib.getExe home.programs.noctalia.package} config validate ${shellConfig} > "$out/noctalia.log" 2>&1 || { cat "$out/noctalia.log"; exit 1; }
    cp ${baseConfig} "$XDG_CONFIG_HOME/noctalia/config.toml"
    cp ${shellConfig} "$XDG_CONFIG_HOME/noctalia-sessions/hyprland.toml"
    ${lib.getExe home.programs.noctalia.package} config export merged > "$out/noctalia-merged.toml" 2> "$out/noctalia-export.log" || { cat "$out/noctalia-export.log"; exit 1; }
    python3 - "$out/noctalia-merged.toml" ${shellConfig} <<'PY'
    import sys, tomllib
    with open(sys.argv[1], 'rb') as source: merged = tomllib.load(source)
    with open(sys.argv[2], 'rb') as source: variant = tomllib.load(source)
    mango_plugins = {'ezequiel/mango_layouts', 'gambled23/mangowm-keymode'}
    assert mango_plugins <= set(merged['plugins']['enabled'])
    assert not any(item in mango_plugins for item in variant['plugins']['enabled'])
    PY
    python3 - ${shellConfig} <<'PY'
    import sys, tomllib
    with open(sys.argv[1], 'rb') as source: config = tomllib.load(source)
    blocked = ('ezequiel/mango_layouts', 'gambled23/mangowm-keymode')
    def forbidden(value):
        return any(value == item or value.startswith(item + ':') for item in blocked)
    assert not any(forbidden(item) for item in config['plugins']['enabled'])
    assert not any(forbidden(item) for item in config['bar']['main']['start'])
    for group in config['bar']['main']['capsule_group']:
        assert not any(forbidden(item) for item in group['members'])
    assert config['hot_corners']['bottom_right']['action'] == 'none'
    PY
    mv "$TMPDIR/runtime-tests.log" "$out/runtime.log"
    touch "$out/passed"
  ''
