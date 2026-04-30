{ lib }:
{
  mkActionBinds =
    action: keys: lib.listToAttrs (map (key: lib.nameValuePair key { inherit action; }) keys);

  mkLockedSpawnShBinds =
    spawnSh: bindings:
    lib.listToAttrs (
      map (
        binding:
        lib.nameValuePair binding.key {
          action = spawnSh binding.cmd;
          allow-when-locked = true;
        }
      ) bindings
    );

  mkWorkspaceBinds =
    field: prefix:
    lib.listToAttrs (
      map (
        index:
        lib.nameValuePair "${prefix}${toString index}" {
          action = {
            "${field}" = index;
          };
        }
      ) (lib.range 1 9)
    );

  mergeMany = lib.foldl' (acc: item: acc // item) { };
}
