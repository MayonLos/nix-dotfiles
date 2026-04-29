{ pkgs, ... }:
{
    programs.clash-verge = {
    enable      = true;
    serviceMode = true;
    tunMode     = true;
  };

  services.resolved = {
    enable      = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };
}