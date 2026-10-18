_: {
  den.aspects = {
    system-maintenance.nixos.imports = [
      ./maintenance/nix.nix
      ./maintenance/locale.nix
      ./maintenance/tools.nix
      ./maintenance/nh.nix
    ];
    legion-laptop.nixos.imports = [
      ./legion-laptop/boot.nix
      ./legion-laptop/firmware.nix
      ./legion-laptop/intel-video.nix
      ./legion-laptop/nvidia.nix
      ./legion-laptop/bluetooth.nix
      ./legion-laptop/power.nix
      ./legion-laptop/memory.nix
    ];
    laptop-network.nixos.imports = [
      ./laptop-network/network.nix
      ./laptop-network/clash.nix
    ];
    closed-ssh-socket.nixos.imports = [ ../remote-access/host.nix ];
  };
}
