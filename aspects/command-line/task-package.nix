{ pkgs }:
pkgs.writeShellApplication {
  name = "workspace-task";
  text = ''
    if [[ $# -eq 0 || $1 == --help ]]; then
      echo '用法：workspace-task [--] 命令 [参数…]'
      echo '命令运行期间阻止普通睡眠请求，结束后自动释放；屏幕仍可自动锁定。'
      [[ $# -gt 0 ]] && exit 0
      exit 2
    fi
    if [[ $1 == -- ]]; then shift; fi
    if [[ $# -eq 0 ]]; then exit 2; fi
    exec ${pkgs.systemd}/bin/systemd-inhibit \
      --what=sleep --mode=block --who='工作台长任务' \
      --why='用户显式启动的长任务正在运行' -- "$@"
  '';
}
