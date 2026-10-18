{
  pkgs,
  ...
}:

let
  zshInit = ''

    # fzf-tab supplies its own height after FZF_DEFAULT_OPTS; override it in
    # fzf-flags (appended last), while sharing the terminal palette with fzf.
    zstyle ':fzf-tab:*' use-fzf-default-opts yes
    zstyle ':fzf-tab:*' fzf-flags \
      '--height=~40%' '--border=rounded' '--border-label= Complete ' \
      '--padding=0,1' '--info=inline' '--prompt=❯ ' '--pointer=▌'
    zstyle ':fzf-tab:*' switch-group '[' ']'
    zstyle ':completion:*' menu no
    zstyle ':completion:*:descriptions' format '[%d]'

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
in
{
  programs = {
    zsh = {
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
        ls = "eza --icons=auto --group-directories-first";
        ll = "eza -l --icons=auto --git --group-directories-first --time-style=long-iso";
        la = "eza -la --icons=auto --git --group-directories-first --time-style=long-iso";
        lt = "eza --tree --level=2 --icons=auto --group-directories-first";
        cat = "bat";
        ".." = "cd ..";
        "..." = "cd ../..";
        nr = "nh os switch";
        nc = "nh clean all";
        lg = "lazygit";
        ff = "fastfetch";
        bt = "btop";
      };

      initContent = zshInit;
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        format = "$username$hostname$directory$git_branch$git_status$all\n$character";

        directory = {
          style = "bold blue";
          truncation_length = 3;
          truncation_symbol = "…/";
          truncate_to_repo = true;
        };
        git_branch.style = "bold purple";
        git_branch.format = "[ $branch]($style) ";
        git_status.style = "yellow";
        cmd_duration = {
          min_time = 3000;
          format = "[· $duration]($style) ";
          style = "dimmed yellow";
        };
        status = {
          # The prompt arrow already turns red on failure; avoid numeric noise
          # after cancelling an interactive picker (exit status 130).
          disabled = true;
        };
        sudo = {
          # Cached sudo credentials do not mean this shell is running as root.
          # The username module still highlights an actual root shell.
          disabled = true;
        };
        line_break.disabled = true;
        username.style_user = "bold cyan";
        username.style_root = "bold red";
        hostname.style = "bold cyan";
      };
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultOptions = [
        "--height=~40%"
        "--layout=reverse"
        "--border=rounded"
        "--padding=0,1"
        "--info=inline"
        "--prompt=❯ "
        "--pointer=▌"
        "--marker=✓"
      ];
      historyWidgetOptions = [ "--border-label= History " ];
      fileWidgetOptions = [ "--border-label= Files " ];
      changeDirWidgetOptions = [
        "--border-label= Directories "
        "--preview=eza --color=always --icons --group-directories-first -- {}"
        "--preview-window=right,45%,border-left"
      ];
      # ANSI roles follow the selected terminal palette without a second renderer.
      colors = {
        fg = "-1";
        bg = "-1";
        "fg+" = "-1";
        "bg+" = "bright-black";
        hl = "yellow";
        "hl+" = "bright-yellow";
        border = "bright-black";
        prompt = "blue";
        pointer = "magenta";
        marker = "green";
        spinner = "cyan";
        header = "bright-black";
        info = "bright-black";
      };
    };
  };
}
