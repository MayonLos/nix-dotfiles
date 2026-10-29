_:

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
}
