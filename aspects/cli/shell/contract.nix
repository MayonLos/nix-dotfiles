{ lib, ... }: {
  options.flakePath = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };
  options.secretExports = lib.mkOption {
    default = [ ];
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_-]+"; };
          variable = lib.mkOption { type = lib.types.strMatching "[A-Z_][A-Z0-9_]*"; };
        };
      }
    );
    description = "Runtime sops secret names exported by the selected interactive shell.";
  };
}
