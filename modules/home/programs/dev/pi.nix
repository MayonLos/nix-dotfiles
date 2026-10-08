{ inputs, pkgs, ... }:
let
  pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  localModels = import ../../../../lib/local-models.nix;
  piLocalModels = map (
    model:
    let
      reasoning = model.id == "qwen3.5-9b";
    in
    {
      inherit (model) id contextWindow;
      name = if model.id == "qwen2.5-coder-7b" then "Qwen2.5 Coder 7B (local)" else "Qwen3.5 9B (local)";
      api = "openai-completions";
      baseUrl = "http://127.0.0.1:8080/v1";
      input = [ "text" ];
      cost = {
        input = 0;
        output = 0;
        cacheRead = 0;
        cacheWrite = 0;
      };
      maxTokens = 2048;
      inherit reasoning;
      compat = {
        supportsStore = false;
        supportsDeveloperRole = false;
        supportsStrictMode = false;
        supportsUsageInStreaming = true;
        maxTokensField = "max_tokens";
        supportsReasoningEffort = false;
      }
      // pkgs.lib.optionalAttrs reasoning {
        thinkingFormat = "qwen-chat-template";
      };
    }
    // pkgs.lib.optionalAttrs reasoning {
      thinkingLevelMap = {
        off = "off";
        minimal = null;
        low = null;
        medium = "medium";
        high = null;
        xhigh = null;
      };
    }
  ) localModels;
  piLocalExtension = pkgs.writeText "pi-local-provider.ts" ''
    export default function (pi) {
      pi.registerProvider("llama-local", {
        baseUrl: "http://127.0.0.1:8080/v1",
        api: "openai-completions",
        apiKey: "local",
        models: ${builtins.toJSON piLocalModels},
      });
    }
  '';
  piLocal = pkgs.writeShellApplication {
    name = "pi-local";
    runtimeInputs = [ pi ];
    text = ''
      for argument in "$@"; do
        case "$argument" in
          --model|--model=*) exec pi --extension ${piLocalExtension} --provider llama-local "$@" ;;
        esac
      done
      exec pi --extension ${piLocalExtension} --provider llama-local --model qwen3.5-9b "$@"
    '';
  };
in
{
  # Keep the local static provider scoped to this wrapper; ordinary Pi retains
  # its built-in providers and user auth/model configuration.
  home.packages = [
    pi
    piLocal
  ];
}
