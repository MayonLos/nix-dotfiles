{ den, ... }: {
  imports = [ ../../appearance/appearance ];
  den.aspects = {
    jetbrains = { host, ... }: {
      homeManager.imports = [ ./jetbrains.nix ];
      provides.${host.name}.includes = [ den.aspects.editing-runtime-host ];
    };
  };
}
