{ inputs, pkgs, ... }:
let
  pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  piLocal = pkgs.writeShellApplication {
    name = "pi-local";
    runtimeInputs = [ pi ];
    text = ''
      export LLAMA_BASE_URL=http://127.0.0.1:8080
      for argument in "$@"; do
        case "$argument" in
          --model|--model=*) exec pi --provider llama.cpp "$@" ;;
        esac
      done
      exec pi --provider llama.cpp --model qwen2.5-coder-7b "$@"
    '';
  };
in
{
  # Pi keeps provider login separate from Codex: use /login and ~/.pi/agent/auth.json.
  # Pi 1.0's built-in llama.cpp provider discovers the local router; /llama
  # manages loading and /model selects a model without duplicating auth data.
  home.packages = [
    pi
    piLocal
  ];
}
