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
  formatter = lib.types.either orderedStrings (
    lib.types.submodule {
      options.lsp_format = lib.mkOption {
        type = lib.types.enum [
          "fallback"
          "prefer"
          "never"
          "first"
          "last"
        ];
      };
    }
  );
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
      neovim.formatters = lib.mkOption {
        type = lib.types.attrsOf formatter;
        default = { };
      };
      neovim.linters = lib.mkOption {
        type = lib.types.attrsOf orderedStrings;
        default = { };
      };
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
          options.formatters = lib.mkOption {
            type = lib.types.attrsOf formatter;
            default = { };
          };
          options.linters = lib.mkOption {
            type = lib.types.attrsOf orderedStrings;
            default = { };
          };
          config.formatters = lib.mkMerge (
            map (entry: entry.neovim.formatters) (lib.attrValues config.languages)
          );
          config.linters = lib.mkMerge (map (entry: entry.neovim.linters) (lib.attrValues config.languages));
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
