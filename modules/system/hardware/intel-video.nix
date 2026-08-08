{ pkgs, ... }:
{
  # i7-14700HX（Raptor Lake）的核显走 VAAPI 需要 iHD 驱动，而 hardware.graphics
  # 的 extraPackages 之前只有 NVIDIA 那几个，/run/opengl-driver/lib/dri/ 下没有
  # iHD_drv_video.so —— 于是任何在 Intel 渲染节点上 vaInitialize 的程序都失败。
  #
  # 注意本机的节点编号和直觉相反：renderD128 是 nvidia，renderD129 才是 i915。
  #
  # 影响面是全系统的：浏览器和 mpv 的硬件解码此前都落在 CPU 上。补上之后
  # vainfo 能列出 H264 / HEVC / AV1 的解码和编码 entrypoint。
  # 用 mkAfter 追加，避免顶掉 nvidia.nix 里已有的项。
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # iHD，Gen8 以上
    vpl-gpu-rt # oneVPL 运行时，Gen12 以上的编解码走它
  ];

  # 排障用：`vainfo --display drm --device /dev/dri/renderD129`
  environment.systemPackages = [ pkgs.libva-utils ];
}
