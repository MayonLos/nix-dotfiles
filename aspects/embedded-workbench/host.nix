{ pkgs, ... }:

{
  # OpenOCD supplies probe matching (ST-Link, CMSIS-DAP, J-Link, etc.). Its
  # rules name plugdev, so declare the empty group to let udev resolve them.
  # No users are added: access still comes from logind's dynamic uaccess ACL.
  #
  # stlink's installed rules instead use final MODE=0666. Normalize those
  # rules to 0660 + uaccess, preserving aliases without world-writable USB.
  # Selecting this host support is not per-account USB device isolation.
  users.groups.plugdev = { };

  services.udev.packages = [
    pkgs.openocd
    (import ./rules.nix { inherit pkgs; })
    # STM32MP157's BootROM, TF-A and U-Boot DFU stages use 0483:df11
    # (ST AN5275). Tag the device before systemd's 71-seat.rules runs.
    (pkgs.writeTextDir "lib/udev/rules.d/70-stm32-dfu.rules" ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="df11", TAG+="uaccess"
    '')
  ];

  # The serial console is the other half, and it is not uaccess-tagged: a
  # USB-serial adapter comes up as /dev/ttyUSB* or /dev/ttyACM* owned by
  # root:dialout. The feature's user class grants that group only to selected
  # accounts. The feature grants dialout only to selecting bindings.
}
