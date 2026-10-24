{ lib, pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  programs.dconf.enable = true;

  virtualisation.spiceUSBRedirection.enable = true;

  # Keep libvirt's activation sockets available while preventing the daemon
  # itself from being pulled in at every boot. Its socket can still activate it.
  # force: Keep libvirt socket activation without starting the daemon at boot.
  systemd.services.libvirtd.wantedBy = lib.mkForce [ ];
  systemd.services.libvirt-guests.enable = false;
}
