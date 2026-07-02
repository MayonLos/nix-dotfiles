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
      nr = "nh os switch";
      nc = "nh clean all";
      lg = "lazygit";
    };
  };

  programs.zsh.initContent = ''
    for _s in deepseek-api-key:DEEPSEEK_API_KEY; do
      _file="/run/secrets/''${_s%%:*}"
      _var="''${_s##*:}"
      [ -r "$_file" ] && export "$_var=$(cat "$_file")"
    done
    unset _s _file _var

    zmodload zsh/terminfo 2>/dev/null
    autoload -U up-line-or-beginning-search down-line-or-beginning-search
    zle -N up-line-or-beginning-search
    zle -N down-line-or-beginning-search
    bindkey "''${terminfo[kcuu1]}" up-line-or-beginning-search
    bindkey "''${terminfo[kcud1]}" down-line-or-beginning-search
    bindkey "^[[A" up-line-or-beginning-search   
    bindkey "^[[B" down-line-or-beginning-search 
    bindkey "^[OA" up-line-or-beginning-search
    bindkey "^[OB" down-line-or-beginning-search
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
