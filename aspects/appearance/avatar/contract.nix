{ lib, ... }:
let
  avatarType = lib.types.nullOr (
    lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Account name used for avatar filenames and AccountsService targets.";
        };
        initial = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Initial rendered in the generated account avatar.";
        };
      };
    }
  );
in
{
  options.avatar = lib.mkOption {
    description = "Optional account avatar identity data for the selected avatar feature.";
    default = null;
    type = avatarType;
  };
}
