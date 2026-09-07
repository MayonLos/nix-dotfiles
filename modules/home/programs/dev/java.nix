{ pkgs, pkgs-unstable, ... }:
let
  temurin = pkgs.javaPackages.compiler.temurin-bin;
  # 26 is not in stable 26.05 yet.
  temurin-unstable = pkgs-unstable.javaPackages.compiler.temurin-bin;
in
{
  home.packages = [
    temurin.jdk-25
    (pkgs.writeShellScriptBin "java8" ''exec ${temurin.jdk-8}/bin/java "$@"'')
    (pkgs.writeShellScriptBin "javac8" ''exec ${temurin.jdk-8}/bin/javac "$@"'')
    (pkgs.writeShellScriptBin "java17" ''exec ${temurin.jdk-17}/bin/java "$@"'')
    (pkgs.writeShellScriptBin "javac17" ''exec ${temurin.jdk-17}/bin/javac "$@"'')
    (pkgs.writeShellScriptBin "java21" ''exec ${temurin.jdk-21}/bin/java "$@"'')
    (pkgs.writeShellScriptBin "javac21" ''exec ${temurin.jdk-21}/bin/javac "$@"'')
    (pkgs.writeShellScriptBin "java25" ''exec ${temurin.jdk-25}/bin/java "$@"'')
    (pkgs.writeShellScriptBin "javac25" ''exec ${temurin.jdk-25}/bin/javac "$@"'')
    (pkgs.writeShellScriptBin "java26" ''exec ${temurin-unstable.jdk-26}/bin/java "$@"'')
    (pkgs.writeShellScriptBin "javac26" ''exec ${temurin-unstable.jdk-26}/bin/javac "$@"'')
  ];
}
