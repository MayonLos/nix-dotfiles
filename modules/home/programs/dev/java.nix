{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

let
  java = import ../../../../lib/java.nix { inherit pkgs pkgs-unstable; };

  # One launcher pair per installed version. The default runs as the profile
  # `java`; the rest are reachable as javaNN/javacNN or via use-javaNN.
  launchers = lib.concatLists (
    lib.mapAttrsToList (version: jdk: [
      (pkgs.writeShellScriptBin "java${version}" ''exec ${jdk}/bin/java "$@"'')
      (pkgs.writeShellScriptBin "javac${version}" ''exec ${jdk}/bin/javac "$@"'')
    ]) java.jdks
  );
in
{
  home.packages = [ java.jdks.${java.default} ] ++ launchers;
}
