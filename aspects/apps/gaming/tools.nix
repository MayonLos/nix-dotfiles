{ pkgs }:
let
  pythonTool =
    name: source: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = ''exec ${pkgs.python3}/bin/python3 ${source} "$@"'';
    };
  # gamemoderun itself execs `env`; don't rely on the launcher's inherited PATH.
  gameRun = pythonTool "game-run" ./resources/game-run.py [
    pkgs.gamemode
    pkgs.coreutils
  ];
in
{
  game-run = gameRun;
  gaming-mode-hook = pythonTool "gaming-mode-hook" ./resources/gamemode-hook.py [
    pkgs.power-profiles-daemon
    pkgs.systemd
  ];
  gamescope-run = pythonTool "gamescope-run" ./resources/gamescope-run.py [
    gameRun
    pkgs.gamescope
    pkgs.wlr-randr
    pkgs.xrandr
  ];
}
