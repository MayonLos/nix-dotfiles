{ pkgs }:
# Virtual-pointer injector used by the isolated mangobar tray test. The sway
# headless backend creates no input devices, so the seat has no pointer
# capability and mangobar would never bind wl_pointer. This client creates a
# real pointer device on the seat and forwards absolute moves / button events.
pkgs.stdenv.mkDerivation {
  pname = "wlr-virtual-pointer-injector";
  version = "0";
  src = ./.;

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.wayland-scanner
  ];
  buildInputs = [
    pkgs.wayland
    pkgs.wlr-protocols
  ];

  buildPhase = ''
    wayland-scanner client-header \
      ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml \
      wlr-virtual-pointer-unstable-v1-client-protocol.h
    wayland-scanner private-code \
      ${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml \
      wlr-virtual-pointer-unstable-v1-protocol.c
    $CC -O2 -Wall -Wextra -I. -o vptr vptr.c \
      wlr-virtual-pointer-unstable-v1-protocol.c \
      $(pkg-config --cflags --libs wayland-client)
  '';

  installPhase = "install -Dm755 vptr $out/bin/vptr";
}
