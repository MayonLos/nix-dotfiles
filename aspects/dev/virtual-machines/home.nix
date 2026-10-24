{ pkgs, ... }:
{
  # Install the management client only. The local hypervisor is selected by
  # the distinct local-virtual-machines feature and its host support aspect.
  home.packages = [ pkgs.virt-manager ];
}
