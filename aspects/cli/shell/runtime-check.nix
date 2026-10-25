{
  pkgs,
  home,
  palette,
  systemPath,
}:
let
  # HM renders absolute home/history/plugin paths. Rebase them for the shell
  # binding test so interactive startup cannot touch the real user's history.
  isolatedZshrc = pkgs.writeText "isolated-zshrc" (
    pkgs.lib.replaceStrings [ home.home.homeDirectory "/run/secrets/" ] [ "$HOME" "$HOME/secrets/" ]
      home.home.file."./.zshrc".text
  );
  visualSettings = pkgs.writeText "cli-visual-settings.json" (
    builtins.toJSON {
      starshipConfig = home.home.file.${home.programs.starship.configPath}.source;
      starship = "${home.programs.starship.package}/bin/starship";
      git = "${pkgs.git}/bin/git";
      tmux = "${pkgs.tmux}/bin/tmux";
      tmuxCurrentFormat = "#[fg=${palette.brightFg},us=${palette.blue},bold,underscore]#I #W#[nounderscore,nobold,us=default]#{?window_zoomed_flag,#[fg=${palette.yellow}]#[bold] Z,}#[default]";
      tmuxUnderlineColor = palette.blue;
      terminfoDirs = [
        "${pkgs.kitty.terminfo}/share/terminfo"
        "${pkgs.ncurses}/share/terminfo"
      ];
      btop = "${home.programs.btop.package}/bin/btop";
      yazi = "${home.programs.yazi.package}/bin/yazi";
      atuin = "${home.programs.atuin.package}/bin/atuin";
      lazygit = "${home.programs.lazygit.package}/bin/lazygit";
      configs = {
        "btop/btop.conf" = home.xdg.configFile."btop/btop.conf".source;
        "btop/themes/One Dark.theme" = home.xdg.configFile."btop/themes/One Dark.theme".source;
        "yazi/theme.toml" = home.xdg.configFile."yazi/theme.toml".source;
        "yazi/yazi.toml" = home.xdg.configFile."yazi/yazi.toml".source;
        "atuin/config.toml" = home.xdg.configFile."atuin/config.toml".source;
        "atuin/themes/onedark.toml" = home.xdg.configFile."atuin/themes/onedark.toml".source;
        "lazygit/config.yml" = home.home.file."${home.xdg.configHome}/lazygit/config.yml".source;
      };
    }
  );
  kittyExtra = pkgs.writeText "kitty-workspace-check.py" ''
    import os, json
    from kitty.config import load_config
    bad = []
    opts = load_config("${home.xdg.configFile."kitty/kitty.conf".source}", accumulate_bad_lines=bad)
    if bad or opts.background_opacity != 1.0 or opts.font_size != 11.0 or opts.confirm_os_window_close[0] != -1:
        raise RuntimeError("Invalid Kitty workspace settings")
    if opts.cursor.as_sharp != "${palette.brightFg}" or opts.selection_foreground.as_sharp != "${palette.brightFg}":
        raise RuntimeError("Invalid cursor/selection roles")
    assert opts.tab_bar_style == "custom"
    assert opts.selection_background.as_sharp == "${palette.selection}"
    assert opts.active_tab_background.as_sharp == "${palette.deep}"
    assert opts.active_tab_foreground.as_sharp == "${palette.brightFg}"
    assert opts.inactive_tab_foreground.as_sharp == "${palette.fg}"
    assert opts.undercurl_style == "thick-sparse"
    assert opts.cursor_trail == ${if palette.reducedMotion or false then "0" else "1"}
    assert opts.cursor_trail_decay == (0.08, 0.16)
    assert opts.cursor_trail_start_threshold == (4, 4)
    assert opts.cursor_trail_color.as_sharp == "${palette.blue}"
    assert tuple(opts.window_padding_width) == (4, 4, 4, 4)
    assert opts.placement_strategy == "top-left"
    assert opts.padding_fill_strategy == "neighboring_cell"
    import ast
    tab_bar = open("${home.xdg.configFile."kitty/tab_bar.py".source}").read()
    ast.parse(tab_bar)
    assert "4:1;58:2::" in tab_bar and "${palette.blue}" in tab_bar
    expected = ${
      builtins.toJSON (
        {
          background = palette.deep;
          foreground = palette.brightFg;
        }
        // pkgs.lib.listToAttrs (
          pkgs.lib.imap0 (i: value: {
            name = "color${toString i}";
            inherit value;
          }) (import ../../appearance/appearance/ansi.nix palette)
        )
      )
    }
    for key, value in expected.items():
        if getattr(opts, key).as_sharp != value:
            raise RuntimeError(f"Kitty palette mismatch: {key}")
    with open(os.environ["KITTY_RESULT"], "w") as result:
        json.dump(expected, result)
  '';
in
assert !(home.xdg.configFile ? "kitty/mayon.conf");
assert !(home.home.activation ? seedKittyConfig);
assert
  home.programs.btop.settings.color_theme == (if palette == null then "Default" else "One Dark");
assert home.programs.delta.options.syntax-theme == home.programs.bat.config.theme;
assert home.home.sessionVariables.BAT_THEME == home.programs.bat.config.theme;
assert !home.programs.tealdeer.enableAutoUpdates;
pkgs.runCommand "command-line-runtime"
  {
    nativeBuildInputs = [
      pkgs.tmux
      pkgs.python3
      pkgs.zsh
      pkgs.git
      home.programs.atuin.package
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$out"
    export BAT_CACHE_PATH=${home.home.sessionVariables.BAT_CACHE_PATH}
    export BAT_THEME='One Dark'
    test -s "$BAT_CACHE_PATH/themes.bin"
    test -s "$BAT_CACHE_PATH/syntaxes.bin"
    ${home.programs.bat.package}/bin/bat --list-themes --color=never | grep -Fx 'One Dark' > "$out/bat-theme.txt"
    cat > "$TMPDIR/sample.py" <<'PY_SAMPLE'
    # One Dark syntax sample
    def greet(name):
        return "hello " + str(42)
    PY_SAMPLE
    ${home.programs.bat.package}/bin/bat --no-config --theme="$BAT_THEME" --color=always --style=plain "$TMPDIR/sample.py" > "$out/bat-sample.ansi"
    ${home.programs.delta.package}/bin/delta --list-syntax-themes | grep -F 'One Dark' > "$out/delta-theme.txt"
    printf '%s\n' 'diff --git a/sample.py b/sample.py' '--- a/sample.py' '+++ b/sample.py' '@@ -1 +1 @@' '-value = 1' '+value = 42' | \
      ${home.programs.delta.package}/bin/delta --no-gitconfig --syntax-theme="$BAT_THEME" --paging=never --true-color=always \
        --plus-style=${pkgs.lib.escapeShellArg home.programs.delta.options.plus-style} \
        --plus-emph-style=${pkgs.lib.escapeShellArg home.programs.delta.options.plus-emph-style} \
        --minus-style=${pkgs.lib.escapeShellArg home.programs.delta.options.minus-style} \
        --minus-emph-style=${pkgs.lib.escapeShellArg home.programs.delta.options.minus-emph-style} > "$out/delta-sample.ansi"
    test -z '${home.home.activation.batCache.data}'
    mkdir -p "$XDG_CONFIG_HOME/eza"
    cp ${home.xdg.configFile."eza/theme.yml".source} "$XDG_CONFIG_HOME/eza/theme.yml"
    ${home.programs.eza.package}/bin/eza --color=always --icons=always "$TMPDIR" > "$out/eza.ansi" 2> "$out/eza.err"
    test ! -s "$out/eza.err"
    ${pkgs.glow}/bin/glow --style ${
      home.xdg.configFile."glow/onedark.json".source
    } ${pkgs.writeText "sample.md" "# One Dark\n\nA **bold** word and `code`.\n"} > "$out/glow.txt"
    ${home.programs.fastfetch.package}/bin/fastfetch --config ${
      home.xdg.configFile."fastfetch/config.jsonc".source
    } --pipe false > "$out/fastfetch.txt" 2> "$out/fastfetch.err"
    test ! -s "$out/fastfetch.err"
    # The build sandbox has no os-release, compositor socket or GPU devices.
    # Those modules remain dynamic and are checked visually after activation.
    grep -F 'Kernel' "$out/fastfetch.txt"
    grep -F 'Terminal' "$out/fastfetch.txt"
    grep -F 'CPU' "$out/fastfetch.txt"
    grep -F 'Memory' "$out/fastfetch.txt"
    for key in OS Kernel WM Terminal CPU GPU Memory; do
      grep -F '"key": "'"$key"'"' ${home.xdg.configFile."fastfetch/config.jsonc".source}
    done
    grep -F '"keyColor": "${palette.blue}"' ${home.xdg.configFile."fastfetch/config.jsonc".source}
    grep -F '"format": "{#${palette.brightFg}}' ${home.xdg.configFile."fastfetch/config.jsonc".source}
    grep -F 'color_theme = "${home.programs.btop.settings.color_theme}"' ${
      home.xdg.configFile."btop/btop.conf".source
    }
    grep -F 'rounded_corners = True' ${home.xdg.configFile."btop/btop.conf".source}
    grep -F 'theme[cpu_start]="${palette.blue}"' ${
      home.xdg.configFile."btop/themes/One Dark.theme".source
    }
    grep -F 'theme[cpu_end]="${palette.cyan}"' ${
      home.xdg.configFile."btop/themes/One Dark.theme".source
    }
    grep -F 'theme[download_start]="${palette.blue}"' ${
      home.xdg.configFile."btop/themes/One Dark.theme".source
    }
    grep -F 'theme[upload_end]="${palette.cyan}"' ${
      home.xdg.configFile."btop/themes/One Dark.theme".source
    }
    python3 - "$out/bat-sample.ansi" "$out/delta-sample.ansi" ${
      home.home.file."${home.xdg.configHome}/tealdeer/config.toml".source
    } <<'PY_CLI'
    import pathlib, sys, tomllib
    for file in sys.argv[1:3]:
        assert b'\x1b[' in pathlib.Path(file).read_bytes(), file
    config = tomllib.loads(pathlib.Path(sys.argv[3]).read_text())
    assert config["updates"]["auto_update"] is True
    PY_CLI
    export KITTY_RESULT="$out/kitty.json"
    ${pkgs.kitty}/bin/kitty +runpy "exec(open('${kittyExtra}').read())"
    test -s "$KITTY_RESULT"
    zsh -n ${home.home.file."./.zshrc".source}
    ln -s ${isolatedZshrc} "$HOME/.zshrc"
    TERM=xterm zsh -i -c 'bindkey "^R"' > "$out/zsh-ctrl-r"
    TERM=xterm zsh -i -c 'bindkey "^T"; bindkey "^[c"; bindkey "^[[A"' > "$out/zsh-fzf-bindings"
    grep -Fq 'atuin-search' "$out/zsh-ctrl-r"
    grep -Fq 'fzf-file-widget' "$out/zsh-fzf-bindings"
    grep -Fq 'fzf-cd-widget' "$out/zsh-fzf-bindings"
    grep -Fq 'up-line-or-beginning-search' "$out/zsh-fzf-bindings"
    python3 - ${home.xdg.configFile."atuin/config.toml".source} ${
      home.xdg.configFile."atuin/themes/onedark.toml".source
    } <<'PY'
    import sys, tomllib
    with open(sys.argv[1], "rb") as source:
        config = tomllib.load(source)
    with open(sys.argv[2], "rb") as source:
        theme = tomllib.load(source)
    assert config["auto_sync"] is False
    assert config["update_check"] is False
    assert config["style"] == "compact"
    assert config["inline_height"] == 20
    assert config["enter_accept"] is False
    assert config["filter_mode"] == "global"
    assert config["filter_mode_shell_up_key_binding"] == "session"
    assert config["theme"]["name"] == "onedark"
    assert theme["theme"]["name"] == "onedark"
    assert set(theme["colors"]) == {
        "Base", "AlertInfo", "AlertWarn", "AlertError", "Annotation",
        "Guidance", "Important", "Title", "Muted"
    }
    PY
    tmux -S "$TMPDIR/tmux.sock" -f ${
      home.xdg.configFile."tmux/tmux.conf".source
    } new-session -d -s validate
    trap 'tmux -S "$TMPDIR/tmux.sock" kill-server || true' EXIT
    tmux -S "$TMPDIR/tmux.sock" show-options -s terminal-features | grep -F 'xterm-kitty:usstyle'
    tmux -S "$TMPDIR/tmux.sock" show-options -s terminal-features | grep -F 'tmux-256color:usstyle'
    test "$(tmux -S "$TMPDIR/tmux.sock" show-options -gv allow-passthrough)" = on
    tmux -S "$TMPDIR/tmux.sock" list-keys -T root > root.keys
    tmux -S "$TMPDIR/tmux.sock" list-keys -T prefix > prefix.keys
    if grep -E 'M-(z|n|p|Tab|[1-9])[[:space:]]' root.keys; then exit 1; fi
    grep -E 'h[[:space:]]+select-pane -L' prefix.keys
    grep -E 'l[[:space:]]+select-pane -R' prefix.keys
    grep -E 'Tab[[:space:]]+last-window' prefix.keys
    tmux -S "$TMPDIR/tmux.sock" list-keys -T copy-mode-vi > "$out/copy-mode.keys"
    grep -E 'h[[:space:]]+send-keys -X cursor-left' "$out/copy-mode.keys"

    python3 ${./resources/visual-check.py} ${visualSettings} "$out"

    ${home.programs.fzf.package}/bin/fzf --filter fixture --color '${
      pkgs.lib.concatStringsSep "," (
        pkgs.lib.mapAttrsToList (name: value: "${name}:${value}") home.programs.fzf.colors
      )
    }' <<<'fixture' > "$out/fzf.txt"
    python3 - ${home.xdg.configFile."yazi/theme.toml".source} <<'PY_YAZI'
    import sys, tomllib
    theme = tomllib.load(open(sys.argv[1], "rb"))
    assert theme["indicator"]["current"]["fg"] == "${palette.blue}"
    assert theme["indicator"]["current"]["bg"] == "${palette.selection}"
    assert theme["indicator"]["padding"]["open"] == "▎"
    PY_YAZI

    mkdir -p spy '项目 with spaces'
    cat > spy/program <<'PY'
    #!${pkgs.python3}/bin/python3
    import json, os, sys
    with open(os.environ['CAPTURE'], 'w') as out:
        json.dump({'cwd': os.getcwd(), 'args': sys.argv[1:]}, out)
    PY
    chmod +x spy/program
    for name in kitty nvim firefox thunar; do ln -s program "spy/$name"; done
    export PATH="$PWD/spy:$PATH" CAPTURE="$out/argv.json"
    cd '项目 with spaces'
    ${home.home.sessionVariables.TERMINAL} 'space path' '$(touch injected)' '"quoted"' ""
    test ! -e injected
    python3 - "$CAPTURE" <<'PY'
    import json, os, sys
    with open(sys.argv[1]) as source: result = json.load(source)
    assert result['cwd'] == os.getcwd()
    assert result['args'] == ['space path', '$(touch injected)', '"quoted"', ""]
    PY
    ${pkgs.runtimeShell} ${home.home.file.".local/bin/thunar-open-terminal".source} 'literal $HOME'
    python3 - "$CAPTURE" <<'PY'
    import json, os, sys
    with open(sys.argv[1]) as source: result = json.load(source)
    assert result == {'cwd': os.getcwd(), 'args': ['literal $HOME']}
    PY
    for desktop in code firefox thunar; do
      test -f ${home.home.path}/share/applications/$desktop.desktop || test -f ${systemPath}/share/applications/$desktop.desktop
    done
    grep -Fq 'text/plain=code.desktop' ${home.xdg.configFile."mimeapps.list".source}
    touch "$out/passed"
  ''
