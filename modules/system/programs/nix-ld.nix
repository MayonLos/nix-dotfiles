{
  pkgs,
  ...
}:
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      xz
      bzip2
      openssl
      libGL
      glib
    ];
  };

}
