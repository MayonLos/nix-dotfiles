{ pkgs, ... }:
{
  # KVM/QEMU full-virtualization stack managed by libvirt.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      # TPM 2.0 emulation — required for Windows 11 guests.
      # (UEFI/OVMF firmware ships by default on 26.05, no config needed.)
      swtpm.enable = true;
    };
  };

  # GUI manager + SPICE USB passthrough / clipboard.
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Disable the suspend/resume-guests-on-shutdown service. It is ordered
  # After=libvirtd, so at shutdown libvirtd stops first and this script can no
  # longer connect ("Can't connect to default, Skipping"), then retries/stalls
  # the shutdown. VMs are managed manually here, so it has nothing to do anyway.
  systemd.services.libvirt-guests.enable = false;

  # Nested virtualization on Intel CPUs (run VMs inside VMs / WSL2-style).
  boot.extraModprobeConfig = "options kvm_intel nested=1";

  # libvirtd: manage VMs without sudo;  kvm: access /dev/kvm.
  users.users.mayon.extraGroups = [
    "libvirtd"
    "kvm"
  ];
}
