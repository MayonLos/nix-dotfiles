{ lib, pkgs, ... }:

let
  seeds = {
    "blank.txt" = "";
    "blank.md" = "";
    "blank.py" = "";
    "blank.sh" = "";
    "blank.lua" = "";
    "blank.nix" = "";
  };
  seedFiles = lib.mapAttrs (name: contents: pkgs.writeText "thunar-template-${name}" contents) seeds;
in
{
  home.activation.seedThunarTemplates = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    templates="$HOME/Templates"
    if [ ! -L "$templates" ]; then
      if [ -e "$templates" ] && [ ! -d "$templates" ]; then
        echo "Refusing to seed Thunar templates: $templates exists and is not a directory" >&2
        exit 1
      fi
      run mkdir -p -- "$templates"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: source: ''
        if [ ! -e "$templates/${name}" ] && [ ! -L "$templates/${name}" ]; then
          run install -m 0644 ${lib.escapeShellArg (toString source)} "$templates/${name}"
        fi
      '') seedFiles
    )}
    fi
  '';
}
