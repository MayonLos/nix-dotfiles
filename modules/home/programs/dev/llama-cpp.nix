{
  config,
  lib,
  pkgs,
  ...
}:

let
  models = import ../../../../lib/local-models.nix;
  llamaCpp = import ../../../../pkgs/llama-cpp.nix { inherit pkgs; };
  modelDir = "${config.home.homeDirectory}/.local/share/llama-cpp/models";

  modelsIni = pkgs.writeText "llama-cpp-models.ini" (
    lib.concatMapStringsSep "\n\n" (model: ''
      [${model.id}]
      model = ${modelDir}/${model.file}
      ctx-size = ${toString model.contextWindow}
      n-gpu-layers = 99
      jinja = true
      parallel = 1
    '') models
  );

  downloadScript = pkgs.writeShellApplication {
    name = "llama-models-download";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      model_dir=${lib.escapeShellArg modelDir}
      mkdir -p -- "$model_dir"
      exec 9>"$model_dir/.download.lock"
      flock 9

      verify_sha256() {
        local expected="$1"
        local file="$2"
        printf '%s  %s\n' "$expected" "$file" \
          | ${pkgs.coreutils}/bin/sha256sum --check --status
      }

      download_one() {
        local file="$1"
        local url="$2"
        local expected="$3"
        local expected_size="$4"
        local target="$model_dir/$file"
        local partial="$target.part"

        if [[ -f "$target" ]] && verify_sha256 "$expected" "$target"; then
          echo "Verified existing model: $file"
          return 0
        fi

        rm -f -- "$target"

        if [[ -f "$partial" ]] && verify_sha256 "$expected" "$partial"; then
          echo "Completed resumed model: $file"
        else
          if [[ -f "$partial" ]] \
            && [[ "$(stat --format=%s "$partial")" -ge "$expected_size" ]]; then
            rm -f -- "$partial"
          fi

          echo "Downloading model: $file"
          ${pkgs.curl}/bin/curl \
            --silent \
            --location \
            --fail \
            --show-error \
            --connect-timeout 30 \
            --speed-limit 1024 \
            --speed-time 120 \
            --retry 8 \
            --retry-delay 2 \
            --retry-all-errors \
            --continue-at - \
            --output "$partial" \
            "$url"

          if ! verify_sha256 "$expected" "$partial"; then
            rm -f -- "$partial"
            echo "SHA-256 verification failed for $file" >&2
            return 1
          fi
        fi

        # The temporary file lives beside the destination, so rename is atomic.
        mv -f -- "$partial" "$target"
        echo "Model ready: $file"
      }

      ${lib.concatMapStringsSep "\n" (model: ''
        download_one \
          ${lib.escapeShellArg model.file} \
          ${lib.escapeShellArg model.url} \
          ${lib.escapeShellArg model.sha256} \
          ${toString model.size}
      '') models}
    '';
  };
in
{
  home.packages = [
    llamaCpp
    downloadScript
  ];

  systemd.user.services.llama-models-download = {
    Unit = {
      Description = "Download and verify local llama.cpp models";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${downloadScript}/bin/llama-models-download";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "60s";
      TimeoutStartSec = 0;
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.llama-cpp = {
    Unit = {
      Description = "Local llama.cpp model router";
    };
    Service = {
      ExecStart = ''
        ${llamaCpp}/bin/llama-server \
          --host 127.0.0.1 \
          --port 8080 \
          --models-preset ${modelsIni} \
          --models-max 1
      '';
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
