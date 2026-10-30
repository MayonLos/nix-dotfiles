_: {
  perSystem =
    { pkgs, ... }:
    let
      # User accepted the SDK license on 2026-10-30. Scope acceptance to this
      # androidenv value; reuse the repository's existing nixpkgs instance.
      androidEnv = pkgs.androidenv.override { licenseAccepted = true; };
      androidPackages = androidEnv.composeAndroidPackages {
        platformVersions = [ "35" ];
        buildToolsVersions = [ "35.0.0" ];
        includeEmulator = true;
        includeSystemImages = true;
        systemImageTypes = [ "default" ];
        abiVersions = [ "x86_64" ];
        includeNDK = false;
        includeCmake = false;
      };
      androidSdk = "${androidPackages.androidsdk}/libexec/android-sdk";
    in
    {
      devShells = {
        android = pkgs.mkShell {
          name = "timetable-android";
          packages = [
            pkgs.gradle
            pkgs.jdk17
            androidPackages.androidsdk
          ];
          JAVA_HOME = "${pkgs.jdk17}";
          ANDROID_HOME = androidSdk;
          ANDROID_SDK_ROOT = androidSdk;
          ORG_GRADLE_PROJECT_enableAndroid = "true";
          GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/build-tools/35.0.0/aapt2";
        };

        # Phase one is JVM-only: no SDK, NDK, emulator or license acceptance.
        timetable-android-core = pkgs.mkShell {
          name = "timetable-android-core";
          packages = [
            pkgs.gradle
            pkgs.jdk17
          ];
          JAVA_HOME = "${pkgs.jdk17}";
        };

        default = pkgs.mkShell {
          name = "default-dev";
          packages = with pkgs; [
            git
            gnumake
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
            clang-tools
            sops
            age
            ssh-to-age
          ];
        };

        cuda = pkgs.mkShell {
          name = "cuda-dev";
          packages = with pkgs.cudaPackages; [
            cudatoolkit
            cudnn
            # cudatoolkit already includes this pinned cuda_nvcc output.
          ];
          CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
        };
      };

      treefmt = {
        projectRootFile = "flake.nix";
        settings.formatter.statix = {
          command = pkgs.writeShellScriptBin "statix-check" ''
            set -euo pipefail
            for file in "$@"; do
              ${pkgs.statix}/bin/statix check "$file"
            done
          '';
          includes = [ "*.nix" ];
        };
        programs = {
          nixfmt.enable = true;
          deadnix = {
            enable = true;
            # Den dispatches by lambda argument shape, including unused names.
            no-lambda-pattern-names = true;
          };
          # Statix is a lint gate; automatic fixes can alter aspect semantics.
          statix.enable = false;
          stylua.enable = true;
          rustfmt = {
            enable = true;
            edition = "2021";
          };
        };
      };
    };
}
