_:
let
  importDir = import ../../lib/import-dir.nix;
in
{
  imports = [ ./hardware.nix ] ++ importDir ../../modules/system;
}
