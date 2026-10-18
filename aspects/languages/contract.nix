{ lib }:
let
  # An ordered command/marker list is one value, never concatenated on merge.
  orderedStrings = lib.types.mkOptionType {
    name = "non-empty ordered string list";
    check =
      value:
      builtins.isList value
      && value != [ ]
      && lib.all builtins.isString value
      && builtins.head value != "";
    merge = lib.mergeEqualOption;
  };
  server = lib.types.submodule {
    options = {
      cmd = lib.mkOption { type = orderedStrings; };
      root_markers = lib.mkOption { type = orderedStrings; };
      filetypes = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        apply = lib.unique;
      };
    };
  };
  language = lib.types.submodule {
    options = {
      id = lib.mkOption { type = lib.types.strMatching "[a-z][a-z0-9-]*"; };
      neovim.servers = lib.mkOption {
        type = lib.types.attrsOf server;
        default = { };
      };
    };
  };
in
{
  collect =
    contributions:
    (lib.evalModules {
      modules = [
        ({ config, ... }: {
          options.languages = lib.mkOption {
            type = lib.types.attrsOf language;
            default = { };
          };
          options.servers = lib.mkOption {
            type = lib.types.attrsOf server;
            default = { };
          };
          config.servers = lib.mkMerge (map (entry: entry.neovim.servers) (lib.attrValues config.languages));
        })
      ]
      ++ map (
        entry:
        assert lib.assertMsg (
          builtins.isAttrs entry
          && builtins.isString (entry.id or null)
          && builtins.match "[a-z][a-z0-9-]*" entry.id != null
        ) "Language contribution needs a stable id";
        {
          languages.${entry.id} = entry;
        }
      ) contributions;
    }).config;
}
