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

    use-java() {
      local java_home_var="$1"
      local java_home="''${(P)java_home_var}"
      if [ -z "$java_home" ]; then
        echo "Unknown Java home: $java_home_var" >&2
        return 1
      fi

      export JAVA_HOME="$java_home"
      path=("''${JAVA_HOME}/bin" "''${(@)path:#''${JAVA8_HOME}/bin}" "''${(@)path:#''${JAVA17_HOME}/bin}" "''${(@)path:#''${JAVA21_HOME}/bin}" "''${(@)path:#''${JAVA25_HOME}/bin}")
      hash -r
      java -version
    }

    use-java8() { use-java JAVA8_HOME; }
    use-java17() { use-java JAVA17_HOME; }
    use-java21() { use-java JAVA21_HOME; }
    use-java25() { use-java JAVA25_HOME; }

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

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
