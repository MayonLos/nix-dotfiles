{ lib, ... }: {
  options.flakePath = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Optional flake directory supplied by a host binding.";
  };
}
