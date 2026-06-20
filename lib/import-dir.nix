let
  importDir =
    dir:
    builtins.concatLists (
      builtins.attrValues (
        builtins.mapAttrs (
          name: type:
          if (type == "regular" || type == "symlink") && builtins.match ".*\\.nix" name != null then
            [ (dir + "/${name}") ]
          else if type == "directory" then
            importDir (dir + "/${name}")
          else
            [ ]
        ) (builtins.readDir dir)
      )
    );
in
importDir
