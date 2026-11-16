{ pkgs }:

# Single source of truth for the Temurin JDKs installed on this host.
# Consumers: aspects/dev/languages/java-tools.nix (packages, javaNN wrappers
# and JAVA*_HOME), java-shell.nix (use-javaNN selectors) and
# aspects/apps/gaming/prismlauncher.nix (Prism's JDK list).
let
  temurin = pkgs.javaPackages.compiler.temurin-bin;
in
{
  # Feature version used for JAVA_HOME and the profile `java` on PATH.
  default = "25";

  jdks = {
    "8" = temurin.jdk-8;
    "17" = temurin.jdk-17;
    "21" = temurin.jdk-21;
    "25" = temurin.jdk-25;
    # The stable channel has no JDK 26.
    "26" = pkgs.unstable.jdk26;
  };
}
