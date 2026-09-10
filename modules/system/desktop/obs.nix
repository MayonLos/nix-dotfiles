{ config, ... }:
{
  # v4l2loopback exists for one job: it is the only way to get a screen into
  # QQ (and Tencent Meeting) on this desktop.
  #
  # Their screen-share pickers are X11-only. Verified 2026-09-10 against
  # qq-3.2.32's binary: it carries XQueryTree / XGetImage / XShmGetImage and
  # has *no* Wayland toplevel enumeration at all -- neither
  # zwlr_foreign_toplevel_manager_v1 nor ext_foreign_toplevel_list_v1 appears,
  # and the only Wayland globals it names are ext_input_manager_v1/ext_input_v1.
  # Under mango's rootless Xwayland there are no X clients to enumerate and no
  # X root window worth grabbing, so the picker comes up with "该应用已无法共享".
  # The org.freedesktop.portal.ScreenCast strings in the binary are Electron's
  # own code, not a path QQ's picker ever takes: with the share dialog open,
  # xdg-desktop-portal-wlr logged zero requests.
  #
  # So the screen has to reach QQ as a *camera* instead: OBS captures through
  # the portal (which works), and writes frames here.
  boot = {
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    kernelModules = [ "v4l2loopback" ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=9 card_label="OBS Virtual Camera" exclusive_caps=1
    '';
  };

  # Notes on the three options that are not obvious:
  #
  #   exclusive_caps=1  the device advertises VIDEO_CAPTURE only while a
  #                     producer is streaming. Chromium-based apps (QQ is
  #                     Electron) skip a node that claims both CAPTURE and
  #                     OUTPUT, so without this it never shows up in QQ's
  #                     camera list at all.
  #   video_nr=9        pin it. `boot.kernelModules` loads v4l2loopback before
  #                     uvcvideo has probed, so unpinned it takes /dev/video0
  #                     and pushes the real webcam to video1/video2 -- an order
  #                     that flips the moment probing timing changes.
  #   card_label        what QQ shows in its camera dropdown. The default is
  #                     "Dummy video device (0x0000)".
  #
  # No `video` group membership is needed: v4l2loopback nodes carry udev's
  # uaccess tag, so logind puts an ACL for the active user on them
  # (`getfacl /dev/video9` shows user:mayon:rw-). Verified 2026-09-10.
}
