{
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # 取代原来 `slurp -d | grim -g | satty` 那条手写管道。
  #
  # mark-shot 把选区、标注、复制、保存、钉到桌面做在一个程序里，README 里明写
  # 是冲着 niri 这类 Wayland 合成器设计的。它内部仍然调用 grim 和 wl-clipboard，
  # 所以那两个包要留着；satty 没别的地方用，已经从 packages.nix 移除。
  #
  # wayscrollshot 是滚动截图（边滚边拼），用来截长网页和长聊天记录 ——
  # 这是原来那套完全没有的能力。它运行时要 slurp 和 grim。
  home.packages = [
    inputs.mark-shot.packages.${system}.default
    inputs.wayscrollshot.packages.${system}.default
  ];
}
