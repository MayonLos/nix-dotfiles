{ pkgs, ... }:
{
  mcsrv-network-runtime = import ./mcsrv-runtime-vm.nix { inherit pkgs; };
}
