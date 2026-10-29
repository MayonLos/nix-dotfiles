{
  palette,
  secretExports ? [ ],
}:
{
  lib,
  pkgs,
  osConfig ? { },
  ...
}:

let
  secretDirectory =
    if secretExports == [ ] then
      ""
    else
      builtins.dirOf osConfig.sops.secrets.${(builtins.head secretExports).name}.path;
  commonSecretDirectory = builtins.all (
    entry: osConfig.sops.secrets.${entry.name}.path == "${secretDirectory}/${entry.name}"
  ) secretExports;
  secretInit = lib.mkIf (secretExports != [ ]) (
    lib.mkBefore (
      if commonSecretDirectory then
        ''
          for _s in ${
            lib.concatMapStringsSep " " (entry: "${entry.name}:${entry.variable}") secretExports
          }; do
            _file="${secretDirectory}/''${_s%%:*}"
            _var="''${_s##*:}"
            [ -r "$_file" ] && export "$_var=$(<"$_file")"
          done
          unset _s _file _var

        ''
      else
        lib.concatMapStrings (entry: ''
          _file=${lib.escapeShellArg osConfig.sops.secrets.${entry.name}.path}
          [ -r "$_file" ] && export "${entry.variable}=$(<"$_file")"
          unset _file
        '') secretExports
    )
  );
  promptColors =
    if palette == null then
      {
        directory = "bold blue";
        branch = "white";
        foreground = "white";
        muted = "bright-black";
        warning = "yellow";
        error = "red";
      }
    else
      {
        directory = "bold ${palette.blue}";
        branch = palette.fg;
        foreground = palette.fg;
        inherit (palette) muted;
        warning = palette.yellow;
        error = palette.red;
      };
  fzfPalette =
    if palette == null then
      {
        fg = "-1";
        bg = "-1";
        gutter = "-1";
        "fg+" = "-1";
        "bg+" = "-1";
        hl = "blue";
        "hl+" = "blue";
        border = "bright-black";
        prompt = "blue";
        pointer = "blue";
        marker = "blue";
        spinner = "cyan";
        header = "bright-black";
        info = "bright-black";
      }
    else
      {
        fg = palette.brightFg;
        bg = "-1";
        gutter = "-1";
        "fg+" = palette.brightFg;
        "bg+" = "-1";
        hl = palette.blue;
        "hl+" = palette.blue;
        inherit (palette) border;
        prompt = palette.blue;
        pointer = palette.blue;
        marker = palette.blue;
        spinner = palette.cyan;
        header = palette.fg;
        info = palette.fg;
      };
  zshInit = ''

    # fzf-tab supplies its own height after FZF_DEFAULT_OPTS; override it in
    # fzf-flags (appended last), while sharing the terminal palette with fzf.
    zstyle ':fzf-tab:*' use-fzf-default-opts yes
    zstyle ':fzf-tab:*' fzf-flags \
      '--height=~40%' '--border=none' '--layout=reverse' \
      '--padding=0' '--info=inline-right' '--no-scrollbar' '--gutter= ' '--prompt=❯ ' '--pointer=▌'
    zstyle ':fzf-tab:*' switch-group '[' ']'
    zstyle ':completion:*' menu no
    zstyle ':completion:*:descriptions' format '[%d]'
    ${lib.optionalString (
      palette != null
    ) "export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=${palette.muted}'"}

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

      initContent = lib.mkMerge [
        secretInit
        zshInit
      ];
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        format = "\${custom.root}$hostname$directory$git_branch$git_status$status$character";
        right_format = "$cmd_duration";

        directory = {
          style = promptColors.directory;
          truncation_length = 3;
          truncation_symbol = "…/";
          truncate_to_repo = true;
        };
        git_branch.style = promptColors.branch;
        git_branch.format = "[ $branch]($style) ";
        git_status = {
          style = promptColors.foreground;
          format = "[($all_status$ahead_behind)]($style) ";
          stashed = "≡$count";
          modified = "~$count";
          staged = "+$count";
          untracked = "?$count";
          deleted = "×$count";
          renamed = "»$count";
          conflicted = "=$count";
        };
        cmd_duration = {
          min_time = 3000;
          format = "[· $duration]($style)";
          style = promptColors.muted;
        };
        nix_shell.disabled = true;
        python.disabled = true;
        nodejs.disabled = true;
        rust.disabled = true;
        golang.disabled = true;
        status = {
          disabled = false;
          symbol = "✘";
          style = promptColors.error;
          format = "[$symbol $status]($style) ";
        };
        character = {
          success_symbol = if palette == null then "[❯](blue)" else "[❯](${palette.blue})";
          error_symbol = if palette == null then "[❯](blue)" else "[❯](${palette.blue})";
        };
        sudo = {
          # Cached sudo credentials do not mean this shell is running as root.
          # The root-only custom module marks an actual root shell.
          disabled = true;
        };
        line_break.disabled = true;

        hostname = {
          ssh_only = true;
          style = if palette == null then "bold cyan" else "bold ${palette.cyan}";
          format = "@[$hostname]($style) ";
        };
        custom.root = {
          command = "${pkgs.coreutils}/bin/id -un";
          when = ''test "$(${pkgs.coreutils}/bin/id -u)" -eq 0'';
          style = promptColors.error;
          format = "[$output]($style) ";
        };
      };
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    atuin = {
      enable = true;
      enableZshIntegration = true;
      flags = [ "--disable-up-arrow" ];
      settings = {
        auto_sync = false;
        update_check = false;
        style = "compact";
        inline_height = 20;
        enter_accept = false;
        filter_mode = "global";
        filter_mode_shell_up_key_binding = "session";
      }
      // lib.optionalAttrs (palette != null) {
        theme.name = "onedark";
      };
      themes = lib.optionalAttrs (palette != null) {
        onedark = {
          theme.name = "onedark";
          colors = {
            Base = palette.fg;
            AlertInfo = palette.green;
            AlertWarn = palette.yellow;
            AlertError = palette.red;
            Annotation = palette.fg;
            Guidance = palette.cyan;
            Important = palette.blue;
            Title = palette.brightFg;
            Muted = palette.fg;
          };
        };
      };
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultOptions = [
        "--height=~40%"
        "--layout=reverse"
        "--border=none"
        "--padding=0"
        "--info=inline-right"
        "--no-scrollbar"
        "--gutter=' '"
        "--prompt='❯ '"
        "--pointer=▌"
        "--marker=✓"
      ];
      historyWidgetOptions = [ "--prompt='History ❯ '" ];
      fileWidgetOptions = [
        "--prompt='Files ❯ '"
        "--preview='bat --color=always --style=plain -- {}'"
        "--preview-window=right,45%,border-left,hidden"
        "--bind=ctrl-/:toggle-preview"
      ];
      changeDirWidgetOptions = [
        "--prompt='Directories ❯ '"
        "--preview='eza --color=always --icons --group-directories-first -- {}'"
        "--preview-window=right,45%,border-left,hidden"
        "--bind=ctrl-/:toggle-preview"
      ];
      # Hex colors make the selected state match the shared palette exactly;
      # without an appearance palette, retain terminal ANSI inheritance.
      colors = fzfPalette;
    };
  };
}
