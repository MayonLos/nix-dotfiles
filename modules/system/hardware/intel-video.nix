{ pkgs, ... }:
{
  # VAAPI on the i7-14700HX (Raptor Lake) iGPU needs the iHD driver, but
  # hardware.graphics.extraPackages only carried the NVIDIA ones, so
  # /run/opengl-driver/lib/dri/ had no iHD_drv_video.so -- every vaInitialize on
  # the Intel render node failed.
  #
  # Note the node numbering on this machine is the opposite of what you would
  # guess: renderD128 is nvidia, renderD129 is i915.
  #
  # The impact was system-wide: hardware decoding in browsers and mpv all fell
  # back to the CPU. With this in place vainfo lists H264 / HEVC / AV1 decode and
  # encode entrypoints.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # iHD, Gen8 and newer
    vpl-gpu-rt # oneVPL runtime, drives codecs on Gen12 and newer
  ];

  # For troubleshooting: `vainfo --display drm --device /dev/dri/renderD129`
  environment.systemPackages = [ pkgs.libva-utils ];
}
