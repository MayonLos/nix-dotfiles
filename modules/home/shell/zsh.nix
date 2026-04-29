_:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };
    shellAliases = {
    };
    history.size = 10000;
    zplug = {
      enable = true;
      plugins = [
        { name = "Aloxaf/fzf-tab"; }
      ];
    };
  };
}
