{ pkgs, pkgs-unstable }:

# Single source of truth for the Temurin JDKs installed on this host.
# Consumers: modules/home/programs/dev/java.nix (packages and javaNN wrappers),
# modules/home/base/session-vars.nix (JAVA*_HOME) and
# modules/home/shell/zsh.nix (use-javaNN selectors).
let
  temurin = pkgs.javaPackages.compiler.temurin-bin;
  # 26 is not in stable 26.05 yet.
  temurin-unstable = pkgs-unstable.javaPackages.compiler.temurin-bin;
in
{
  # Feature version used for JAVA_HOME and the profile `java` on PATH.
  default = "25";

  jdks = {
    "8" = temurin.jdk-8;
    "17" = temurin.jdk-17;
    "21" = temurin.jdk-21;
    "25" = temurin.jdk-25;
    "26" = temurin-unstable.jdk-26;
  };
}
