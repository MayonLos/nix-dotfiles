{
  pkgs,
  ...
}:

{
  programs.codex = {
    enable = true;
    package = pkgs.codex;
    settings = {
      # You currently use ChatGPT account login, so force this auth method.
      forced_login_method = "chatgpt";
      model_provider = "openai";
      model = "gpt-5";

      # API key auth placeholder (disabled by default):
      # model_providers.openai.env_key = "OPENAI_API_KEY";

      # Optional local model example (Ollama):
      # model = "gemma3:latest";
      # model_provider = "ollama";
      # model_providers.ollama = {
      #   name = "Ollama";
      #   baseURL = "http://localhost:11434/v1";
      #   envKey = "OLLAMA_API_KEY";
      # };
    };
  };
}
