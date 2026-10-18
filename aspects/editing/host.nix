{
  pkgs,
  ...
}:
{
  programs.nix-ld = {
    enable = true;
    # Libraries that unpatched, downloaded-at-runtime binaries keep asking for.
    # fontconfig/libx11 were added after two separate incidents of the same shape
    # (JetBrains' bundled libskiko, VS Code extension binaries) where a vendor
    # blob failed to load purely because a common system library was absent.
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      xz
      bzip2
      openssl
      libGL
      glib
      fontconfig
      libx11
    ];
  };
}
