{ pkgs, ... }:
{
  # Cycles GPU devices are selected in Blender's preferences and per scene;
  # NVIDIA PRIME offload is already configured in system/hardware/nvidia.nix.
  home.packages = [ pkgs.blender ];
}
