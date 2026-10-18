{ lib, ... }:
let
  color = lib.types.strMatching "#[0-9a-fA-F]{6}";
  roles = [
    "black"
    "bg"
    "surface"
    "selection"
    "border"
    "deep"
    "fg"
    "muted"
    "purple"
    "green"
    "orange"
    "blue"
    "yellow"
    "cyan"
    "red"
    "brightFg"
  ];
in
{
  options.appearance = lib.mkOption {
    description = "Optional palette data for explicitly selected application adapters.";
    default = null;
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.nonEmptyStr; };
          reducedMotion = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Reduce desktop transitions and continuous decorative motion in selected adapters.";
          };
          fonts = lib.mkOption {
            type = lib.types.submodule {
              options = lib.genAttrs [ "sans" "mono" "serif" ] (
                _: lib.mkOption { type = lib.types.nonEmptyStr; }
              );
            };
          };
          cursor = lib.mkOption {
            type = lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.nonEmptyStr; };
                size = lib.mkOption { type = lib.types.ints.positive; };
              };
            };
          };
          iconTheme = lib.mkOption { type = lib.types.nonEmptyStr; };
        }
        // lib.genAttrs roles (_: lib.mkOption { type = color; });
      }
    );
  };
}
