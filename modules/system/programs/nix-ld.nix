{
  pkgs,
  ...
}:
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib   # libstdc++.so.6
      zlib               # libz.so.1
      xz                 # liblzma.so.5
      bzip2              # libbz2.so.1.0
      openssl            # libssl.so, libcrypto.so
      libGL              # OpenGL (matplotlib backend)
      glib               # GObject
    ];
  };

}
