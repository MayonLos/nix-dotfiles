{ den, ... }: {
  imports = [ ../../appearance/appearance ];
  den.aspects = {
    editing-runtime-host.nixos.imports = [ ./host.nix ];
  };
}
