{ lib, ... }:
let
  inherit (lib) types;

  # argv is one command value. Equal definitions coalesce; conflicting values
  # fail instead of being concatenated into a different command.
  singleValue =
    name: check:
    types.mkOptionType {
      inherit name;
      description = "a single ${name} value (equal definitions may be repeated)";
      inherit check;
      merge = lib.mergeEqualOption;
    };

  argvType = singleValue "argv" (
    value:
    builtins.isList value
    && value != [ ]
    && builtins.all builtins.isString value
    && builtins.head value != ""
  );

  desktopIdType = types.addCheck types.str (
    value: builtins.match "[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)*[.]desktop" value != null
  );

  commandType = types.submodule {
    options.argv = lib.mkOption {
      type = argvType;
      description = "Ordered executable and arguments, with a non-empty executable.";
    };
  };

  appType = types.submodule {
    options = {
      argv = lib.mkOption {
        type = argvType;
        description = "Ordered executable and arguments, with a non-empty executable.";
      };
      desktopId = lib.mkOption {
        type = types.nullOr desktopIdType;
        default = null;
        description = "Optional desktop file ID, including the .desktop suffix.";
      };
    };
  };
in
{
  options.defaultTools = lib.mkOption {
    description = "Per-user defaults for command and desktop entry points.";
    default = { };
    type = types.submodule {
      options = {
        terminal = lib.mkOption {
          type = types.nullOr commandType;
          default = null;
        };
        editor = lib.mkOption {
          type = types.nullOr commandType;
          default = null;
        };
        browser = lib.mkOption {
          type = types.nullOr appType;
          default = null;
        };
        fileManager = lib.mkOption {
          type = types.nullOr appType;
          default = null;
        };
        guiTextEditor = lib.mkOption {
          type = types.nullOr desktopIdType;
          default = null;
          description = "Desktop ID for GUI text MIME types; independent of CLI editor.";
        };
      };
    };
  };
}
