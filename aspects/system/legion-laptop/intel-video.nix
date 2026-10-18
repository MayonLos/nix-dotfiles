{ pkgs, ... }:
{
  # VAAPI on the i7-14700HX (Raptor Lake) iGPU needs the iHD driver, but
  # hardware.graphics.extraPackages only carried the NVIDIA ones, so
  # /run/opengl-driver/lib/dri/ had no iHD_drv_video.so -- every vaInitialize on
  # the Intel render node failed.
  #
  # Node numbers are not stable. As of 2026-09 on this machine, renderD128 is
  # i915 (0000:00:02.0) and renderD129 is nvidia. Confirm with
  # /sys/class/drm/renderD*/device/driver before trusting a node.
  #
  # The impact was system-wide: hardware decoding in browsers and mpv all fell
  # back to the CPU. With this in place vainfo lists H264 / HEVC / AV1 decode and
  # encode entrypoints.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # iHD, Gen8 and newer
    vpl-gpu-rt # oneVPL runtime, drives codecs on Gen12 and newer
  ];

  # For troubleshooting: `vainfo --display drm --device /dev/dri/renderD128`
  environment.systemPackages = [ pkgs.libva-utils ];
}
