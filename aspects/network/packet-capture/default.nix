{ den, ... }: {
  den.aspects = {
    packet-capture = { host, user, ... }: {
      # The wrapper created below is readable by this group; membership is the
      # per-user access decision and belongs to the user class.
      user.extraGroups = [ "wireshark" ];
      provides.${host.name}.includes = [ den.aspects.packet-capture-host ];
    };
    packet-capture-host.nixos = { pkgs, ... }: {
      # programs.wireshark installs the GUI system-wide and, with its dumpcap
      # wrapper, gives the wireshark group capture without running as root.
      # Set the package explicitly: the module defaults to wireshark-cli.
      programs.wireshark = {
        enable = true;
        package = pkgs.wireshark;
        dumpcap.enable = true;
      };
    };
  };
}
