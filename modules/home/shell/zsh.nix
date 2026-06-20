{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "fzf-tab";
        src = "${pkgs.zsh-fzf-tab}/share/fzf-tab";
      }
    ];

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      share = true;
    };

    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons --git";
      la = "eza -la --icons --git";
      lt = "eza --tree --icons";
      cat = "bat";
      ".." = "cd ..";
      "..." = "cd ../..";
      nr = "nh os switch ~/nix-dotfiles";
      nc = "nh clean all";
      lg = "lazygit";
    };
  };

  # Load API keys from sops-decrypted files (only if present, so the shell
  # still works before secrets are set up). Each is owned by mayon at /run/secrets.
  programs.zsh.initContent = ''
    # Load API keys from sops-decrypted files (only if present).
    for _s in deepseek-api-key:DEEPSEEK_API_KEY; do
      _file="/run/secrets/''${_s%%:*}"
      _var="''${_s##*:}"
      [ -r "$_file" ] && export "$_var=$(cat "$_file")"
    done
    unset _s _file _var

    # Prefix history search: type the start of a command, then ↑/↓ cycle only
    # through history entries beginning with what's typed (oh-my-zsh behaviour,
    # no framework needed). On an empty line ↑/↓ behave like normal history.
    zmodload zsh/terminfo 2>/dev/null
    autoload -U up-line-or-beginning-search down-line-or-beginning-search
    zle -N up-line-or-beginning-search
    zle -N down-line-or-beginning-search
    bindkey "''${terminfo[kcuu1]}" up-line-or-beginning-search
    bindkey "''${terminfo[kcud1]}" down-line-or-beginning-search
    bindkey "^[[A" up-line-or-beginning-search   # ↑ fallback
    bindkey "^[[B" down-line-or-beginning-search # ↓ fallback
    bindkey "^[OA" up-line-or-beginning-search   # ↑ application-keypad mode
    bindkey "^[OB" down-line-or-beginning-search # ↓ application-keypad mode
  '';

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
