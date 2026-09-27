{ pkgs, ... }:

let
  zshInit = ''
    for _s in deepseek-api-key:DEEPSEEK_API_KEY; do
      _file="/run/secrets/''${_s%%:*}"
      _var="''${_s##*:}"
      [ -r "$_file" ] && export "$_var=$(cat "$_file")"
    done
    unset _s _file _var

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

    use-java() {
      local java_home_var="$1"
      local java_home="''${(P)java_home_var}"
      if [ -z "$java_home" ]; then
        echo "Unknown Java home: $java_home_var" >&2
        return 1
      fi

      export JAVA_HOME="$java_home"
      path=("''${JAVA_HOME}/bin" "''${(@)path:#''${JAVA8_HOME}/bin}" "''${(@)path:#''${JAVA17_HOME}/bin}" "''${(@)path:#''${JAVA21_HOME}/bin}" "''${(@)path:#''${JAVA25_HOME}/bin}" "''${(@)path:#''${JAVA26_HOME}/bin}")
      hash -r
      java -version
    }

    use-java8() { use-java JAVA8_HOME; }
    use-java17() { use-java JAVA17_HOME; }
    use-java21() { use-java JAVA21_HOME; }
    use-java25() { use-java JAVA25_HOME; }
    use-java26() { use-java JAVA26_HOME; }

    # Point LUA_PATH/LUA_CPATH at `luarocks install --local` trees.
    # On demand rather than global: neovim honours LUA_PATH too, and its
    # LuaJIT must not pick up Lua 5.4 rocks.
    use-luarocks() {
      if ! command -v luarocks >/dev/null; then
        echo "luarocks not found" >&2
        return 1
      fi
      eval "$(luarocks path)"
      echo "LUA_PATH/LUA_CPATH set for $(lua -v 2>&1)"
    }
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
      # ANSI named colours, not hex. fzf renders inside kitty, and
      # kitty's palette is rewritten by noctalia on every theme change (the
      # `include themes/noctalia.conf` in programs/terminal/kitty.nix) -- so an
      # ANSI name tracks the desktop for free while a hex value silently becomes
      # the odd one out. `-1` is fzf's "leave it to the terminal", which is
      # also what keeps kitty's `background_opacity 0.8` visible behind the
      # list. Same reasoning as the status bar in programs/terminal/tmux.nix.
      # The zstyle above explicitly opts fzf-tab into FZF_DEFAULT_OPTS.
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
