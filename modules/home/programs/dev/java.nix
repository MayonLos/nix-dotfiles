{ pkgs, ... }:
let
  temurin = pkgs.javaPackages.compiler.temurin-bin;
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
  ];
}
