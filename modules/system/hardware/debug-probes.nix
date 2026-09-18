{ pkgs, ... }:

{
  # Debug probes enumerate as plain USB devices, which means root-only access
  # until something gives the seat's user a claim on them. Both packages ship
  # the udev rules upstream maintains (ST-Link V2/V2-1/V3, CMSIS-DAP, J-Link,
  # and the rest of OpenOCD's interface list); installing them here is what
  # makes `openocd`, `st-flash` and `probe-rs` work without sudo.
  #
  # The rules tag the devices `uaccess`, so logind grants the *currently
  # logged-in* user access dynamically -- no plugdev group, and nothing to add
  # to modules/system/user/mayon.nix for the probes themselves.
  services.udev.packages = [
    pkgs.openocd
    pkgs.stlink
  ];

  # The serial console is the other half, and it is not uaccess-tagged: a
  # USB-serial adapter comes up as /dev/ttyUSB* or /dev/ttyACM* owned by
  # root:dialout. `tio /dev/ttyACM0` needs group membership, which is set in
  # modules/system/user/mayon.nix.
}
