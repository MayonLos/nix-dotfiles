_:
let
  inherit (import ../../lib) importDir;
in
{
  imports = [ ./hardware.nix ] ++ importDir ../../modules/system;
}
