{ pkgs }:
pkgs.runCommand "project-workbench-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.tmux
      pkgs.tmuxp
    ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    WORKSPACE_TMUX_INTEGRATION=1 \
      WORKSPACE_TMUX=${pkgs.tmux}/bin/tmux \
      WORKSPACE_TMUXP=${pkgs.tmuxp}/bin/tmuxp \
      ${pkgs.python3}/bin/python3 ${./.}/tests.py -v
    touch "$out"
  ''
