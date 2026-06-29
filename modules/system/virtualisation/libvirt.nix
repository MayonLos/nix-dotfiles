{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  systemd.services.libvirt-guests.enable = false;
  boot.extraModprobeConfig = "options kvm_intel nested=1";

  users.users.mayon.extraGroups = [
    "libvirtd"
    "kvm"
  ];
}
