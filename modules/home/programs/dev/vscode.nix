{ pkgs, ... }:
{
  # The FHS variant, rather than patching LD_LIBRARY_PATH onto plain vscode.
  #
  # Extension-shipped prebuilt binaries need a pile of system libraries and fail
  # silently when one is missing: cpptools' OpenDebugAD7 wants libstdc++, and
  # back when STM32Cube was installed its node-usb binding also wanted
  # libudev.so.1 -- the hand-rolled wrapper only carried stdenv.cc.cc.lib +
  # libusb1, never covered libudev, and turned into endless whack-a-mole.
  # vscode-fhs' targetPkgs already include udev/libudev0-shim/glibc/icu/nss and
  # friends, which settles the whole class at once. To add more libraries, use
  # pkgs.vscode.fhsWithPackages (ps: [ ... ]).
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
  };
}
