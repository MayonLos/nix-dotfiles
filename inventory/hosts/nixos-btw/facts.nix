# Real instance facts; no service selection or deployment defaults.
{
  system = "x86_64-linux";
  gpu = {
    gameModeDevice = 0; # Preserve the existing NVIDIA tuning index.
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
  display = {
    name = "eDP-1";
    scale = 1.5;
    width = 2560;
    height = 1600;
    refresh = 165.002;
    x11Dpi = 144;
  };
}
