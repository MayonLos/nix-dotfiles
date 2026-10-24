# Virtual machine tools

Provides separate client and local-host selections. `virtual-machine-client` installs virt-manager only. `local-virtual-machines` selects the client, configures the system connection, grants `libvirtd` and `kvm` groups, and routes the local hypervisor host module once.

The host output enables libvirtd with QEMU/KVM and SPICE USB redirection while leaving the daemon service socket-activated rather than wanted at boot. `default.nix`, `home.nix`, and `host.nix` are private. The host feature is opt-in; selecting only the client does not start or enable a daemon.

Removing either selection removes only its corresponding package or service/group declarations after activation. VM images, snapshots, firmware, virtual disks, and guest data remain on disk.
