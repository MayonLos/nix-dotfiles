# Real instance facts; no service selection or deployment defaults.
{
  system = "x86_64-linux";
  gpu = {
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
  keyboardDevices = [
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
    "/dev/input/by-id/usb-ITE_Tech._Inc._ITE_Device_8176_-event-kbd"
  ];
  display = {
    name = "eDP-1";
    scale = 1.5;
    width = 2560;
    height = 1600;
    refresh = 165.002;
    x11Dpi = 144;
  };
}
