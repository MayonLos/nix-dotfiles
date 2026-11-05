{ palette }:
{ lib, pkgs, ... }:
{
  # The FHS variant, rather than patching LD_LIBRARY_PATH onto plain vscode.
  #
  # Extension-shipped prebuilt binaries need a pile of system libraries and fail
  # silently when one is missing: cpptools' OpenDebugAD7 wants libstdc++, and
  # back when STM32Cube was installed its node-usb binding also wanted
  # libudev.so.1 -- the hand-rolled wrapper only carried stdenv.cc.cc.lib +
  # libusb1, never covered libudev, and turned into endless whack-a-mole.
  # vscode-fhs' targetPkgs already include udev/libudev0-shim/glibc/icu/nss and
  # friends, which settles the whole class at once. To add more libraries, use
  # pkgs.vscode.fhsWithPackages (ps: [ ... ]).
  programs.vscode = {
    enable = true;
    package = pkgs.vscode-fhs;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      zhuangtongfa.material-theme
      bbenoist.nix
      # Not in nixpkgs. It runs `probe-rs dap-server` from PATH (supplied by
      # embedded-workbench) and must match that probe-rs release; checks.nix
      # fails when nixpkgs moves probe-rs-tools to another version.
      (pkgs.vscode-utils.extensionFromVscodeMarketplace {
        publisher = "probe-rs";
        name = "probe-rs-debugger";
        version = "0.31.0";
        hash = "sha256-LZ00tkx7MR9SoIBFjh+3AoOsLlAwhhNeif4UeQr4F7A=";
      })
    ];
  };
  assertions = [
    {
      assertion = palette != null;
      message = "Select an appearance for the VS Code workbench defaults";
    }
  ];
  home.activation.seedVscodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 ${./seed-settings.py} ${
      pkgs.writeText "vscode-defaults.json" (builtins.toJSON (import ./settings.nix { inherit palette; }))
    }
  '';
}
