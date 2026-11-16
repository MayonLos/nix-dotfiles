{ pkgs, ... }:
{
  # Cycles GPU devices are selected in Blender's preferences and per scene;
  # NVIDIA PRIME offload is configured by aspects/hardware/legion-laptop/nvidia.nix.
  home.packages = [ pkgs.blender ];
}
