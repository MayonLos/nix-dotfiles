{ den, ... }:
{
  den.aspects.virtual-machine-client.homeManager.imports = [ ./home.nix ];

  den.aspects.local-virtual-machines = { host, ... }: {
    includes = [ den.aspects.virtual-machine-client ];
    homeManager.dconf.settings."org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
    user.extraGroups = [
      "libvirtd"
      "kvm"
    ];
    provides.${host.name}.includes = [ den.aspects.local-virtual-machines-host-support ];
  };

  # Select this provider only for a real host that will run local VMs.
  den.aspects.local-virtual-machines-host-support.nixos.imports = [ ./host.nix ];
}
