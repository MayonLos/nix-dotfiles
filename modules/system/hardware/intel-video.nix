{ pkgs, ... }:
{
  # i7-14700HX（Raptor Lake）的核显走 VAAPI 需要 iHD 驱动，而 hardware.graphics
  # 的 extraPackages 之前只有 NVIDIA 那几个，/run/opengl-driver/lib/dri/ 下没有
  # iHD_drv_video.so —— 于是任何在 Intel 渲染节点上 vaInitialize 的程序都失败。
  #
  # 注意本机的节点编号和直觉相反：renderD128 是 nvidia，renderD129 才是 i915。
  #
  # 这不只是录屏的事：浏览器、mpv 的硬件解码同样吃这个，缺了就全落到 CPU 上。
  # 用 mkAfter 追加，避免顶掉 nvidia.nix 里已有的项。
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # iHD，Gen8 以上
    vpl-gpu-rt # oneVPL 运行时，Gen12 以上的编解码走它
  ];

  # 排障用：`vainfo --display drm --device /dev/dri/renderD129` 应该列出
  # VAProfileH264 / HEVC / AV1 的 Entrypoint。
  environment.systemPackages = [ pkgs.libva-utils ];

  # gpu-screen-recorder 的 gsr-kms-server 需要 CAP_SYS_ADMIN 才能抓 KMS 画面，
  # 否则每次录制都会弹 root 认证或直接失败。这个 NixOS 模块负责做 setcap 包装，
  # 比手工 `sudo setcap` 可靠（手工做的会在下次 GC 后失效）。
  programs.gpu-screen-recorder.enable = true;
}
