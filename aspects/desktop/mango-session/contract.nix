{ lib }:
let
  ids = [
    "btop"
    "vscode"
    "obsidian"
    "zathura"
    "firefox"
    "yazi"
    "avatar"
  ];
  entry = lib.types.submodule {
    options = {
      id = lib.mkOption { type = lib.types.enum ids; };
      templateFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
      hookDirectory = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };
    };
  };
in
{
  # User-scope data only. Equal IDs merge; incompatible payloads fail.
  # No user -> host pipe and no implicit feature selection.
  collect =
    contributions:
    let
      checked =
        (lib.evalModules {
          modules = [
            {
              options.entries = lib.mkOption {
                type = lib.types.attrsOf entry;
                default = { };
              };
            }
          ]
          ++ map (
            value:
            let
              contribution = if builtins.isString value then { id = value; } else value;
            in
            {
              entries.${contribution.id} = contribution;
            }
          ) contributions;
        }).config.entries;
    in
    {
      entries = checked;
      ids = builtins.attrNames checked;
    };
}
