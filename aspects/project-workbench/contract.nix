{ lib, ... }:
let
  inherit (lib) types;

  absoluteDirectory = types.addCheck types.str (
    value:
    lib.hasPrefix "/" value
    && !(lib.hasInfix "\n" value)
    && !(lib.hasInfix "\r" value)
    && builtins.all (part: part != "..") (lib.splitString "/" value)
  );

  project = types.submodule {
    options = {
      directory = lib.mkOption {
        type = absoluteDirectory;
        description = "Absolute project directory; it must already exist at launch time.";
      };
      label = lib.mkOption {
        type = types.addCheck types.nonEmptyStr (
          value: !(lib.hasInfix "\n" value) && !(lib.hasInfix "\r" value) && !(lib.hasInfix "\t" value)
        );
        description = "Human-readable launcher label; treated as plain text.";
      };
    };
  };
in
{
  options.workspaceProjects = lib.mkOption {
    type = types.attrsOf project;
    default = { };
    description = "Explicit per-user project launchers. This option installs no project tools.";
  };
}
