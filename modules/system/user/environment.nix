{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    wget
    lshw
    gnumake
    unzip
    unrar
  ];
}
