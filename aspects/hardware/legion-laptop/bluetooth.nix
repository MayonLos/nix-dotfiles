{ onboard, dongle }:
{ lib, pkgs, ... }:

let
  cat = "${pkgs.coreutils}/bin/cat";
  # Measured on the Intel CNVi radio: A2DP to the Edifier headset stalled
  # (ACL TX 0-21 packets per 10 s, "Missing completion reports") across
  # firmware and BIOS updates. While the dongle is plugged in, only the
  # onboard Bluetooth USB device is deauthorized; Wi-Fi is a separate PCIe
  # function. Unplugging the dongle authorizes the onboard radio again.
  selectAdapter = pkgs.writeShellScript "bt-adapter-select" ''
    present=0
    for d in /sys/bus/usb/devices/*; do
      [ -r "$d/idVendor" ] || continue
      [ "$(${cat} "$d/idVendor"):$(${cat} "$d/idProduct")" = "${dongle}" ] && present=1
    done
    for d in /sys/bus/usb/devices/*; do
      [ -r "$d/idVendor" ] || continue
      if [ "$(${cat} "$d/idVendor"):$(${cat} "$d/idProduct")" = "${onboard}" ]; then
        want=$((1 - present))
        [ "$(${cat} "$d/authorized")" = "$want" ] || echo "$want" > "$d/authorized"
      fi
    done
  '';
  # udev PRODUCT is "vendor/product/bcd" in hex without leading zeros.
  product =
    id:
    let
      parts = lib.splitString ":" id;
      trim = s: lib.toLower (lib.removePrefix "0" (lib.removePrefix "0" (lib.removePrefix "0" s)));
    in
    "${trim (builtins.elemAt parts 0)}/${trim (builtins.elemAt parts 1)}/*";
in
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # LE Audio/BAP needs the kernel ISO socket, which this host does not
        # enable. Keep experimental profiles disabled; classic A2DP is stable
        # BlueZ behavior and remains available.
        Experimental = false;
        FastConnectable = true;
      };
    };
  };

  # Re-evaluated when either radio appears or the dongle goes away, so boot
  # order does not matter.
  services.udev.extraRules = lib.mkIf (onboard != "" && dongle != "") ''
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${product dongle}", RUN+="${selectAdapter}"
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="${product onboard}", RUN+="${selectAdapter}"
  '';
}
