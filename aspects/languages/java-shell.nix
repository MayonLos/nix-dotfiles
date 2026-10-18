{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:
let
  java = import ../../lib/java.nix { inherit pkgs pkgs-unstable; };

  # Built from the same JDK set as java.nix and session-vars.nix, so the
  # selectors cannot drift from what is installed.
  javaSwitchFns = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (version: _: "use-java${version}() { use-java JAVA${version}_HOME; }") java.jdks
  );
  javaPathCleanup = lib.concatMapStringsSep "\n" (
    version: ''path=("''${(@)path:#''${JAVA${version}_HOME}/bin}")''
  ) (lib.attrNames java.jdks);

in
{
  programs.zsh.initContent = ''
    use-java() {
      local java_home_var="$1"
      local java_home="''${(P)java_home_var}"
      if [ -z "$java_home" ]; then
        echo "Unknown Java home: $java_home_var" >&2
        return 1
      fi

      export JAVA_HOME="$java_home"
      ${javaPathCleanup}
      path=("''${JAVA_HOME}/bin" "''${path[@]}")
      hash -r
      java -version
    }

    ${javaSwitchFns}
  '';
}
