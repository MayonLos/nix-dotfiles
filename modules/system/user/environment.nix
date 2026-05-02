{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    wget
    lshw
    gnumake
    unzip
    ripgrep
  ];
}
