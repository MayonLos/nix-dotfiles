{
  pkgs,
  lib,
  ...
}:

let
  java = import ../../../lib/java.nix { inherit pkgs; };

  environment = {
    JAVA_HOME = "${java.jdks.${java.default}}";
  }
  // lib.mapAttrs' (version: jdk: lib.nameValuePair "JAVA${version}_HOME" "${jdk}") java.jdks;

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
  imports = [ ./java-shell.nix ];
  home = {
    sessionPath = [ "${java.jdks.${java.default}}/bin" ];
    sessionVariables = environment;
    packages = [ java.jdks.${java.default} ] ++ launchers;

    # Gradle uses the same JDKs as the shell and Prism rather than downloading
    # another set into ~/.gradle/jdks. Paths track the pinned Nix packages.
    file.".gradle/gradle.properties".text = ''
      org.gradle.java.installations.paths=${lib.concatStringsSep "," (map toString (lib.attrValues java.jdks))}
      org.gradle.java.installations.auto-download=false
    '';
  };
  systemd.user.sessionVariables = environment;

}
