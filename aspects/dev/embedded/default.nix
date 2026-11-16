{ den, ... }:
{
  den.aspects.embedded-workbench = { host, ... }: {
    includes = [ den.aspects.mayon-tools ];
    homeManager = { pkgs, ... }: {
      imports = [ ./home.nix ];
      # Declare these common build tools explicitly rather than taking the
      # whole host LLVM set.
      home.packages = with pkgs; [
        cmake
        ninja
        pkg-config
        gdb
      ];
    };
    user.extraGroups = [ "dialout" ];
    provides.${host.name}.includes = [ den.aspects.embedded-workbench-host ];
  };

  # A named host aspect keeps package/rule contributions independent of users.
  den.aspects.embedded-workbench-host.nixos.imports = [
    ./host.nix
  ];
}
