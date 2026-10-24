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
  kittyExtra = pkgs.writeText "kitty-workspace-check.py" ''
    import os, json
    from kitty.config import load_config
    bad = []
    opts = load_config("${home.xdg.configFile."kitty/kitty.conf".source}", accumulate_bad_lines=bad)
    if bad or opts.background_opacity != 1.0 or opts.font_size != 11.0 or opts.confirm_os_window_close[0] != -1:
        raise RuntimeError("Invalid Kitty workspace settings")
    if opts.cursor.as_sharp != "${palette.brightFg}" or opts.selection_foreground.as_sharp != "${palette.brightFg}":
        raise RuntimeError("Invalid cursor/selection roles")
    expected = ${
      builtins.toJSON (
        {
          background = palette.bg;
          foreground = palette.fg;
        }
        // pkgs.lib.listToAttrs (
          pkgs.lib.imap0 (i: value: {
            name = "color${toString i}";
            inherit value;
          }) (import ../appearance/ansi.nix palette)
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
pkgs.runCommand "command-line-runtime"
  {
    nativeBuildInputs = [
      pkgs.tmux
      pkgs.python3
      pkgs.zsh
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$out"
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
      home.xdg.configFile."atuin/themes/onedark-darker.toml".source
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
    assert config["theme"]["name"] == "onedark-darker"
    assert theme["theme"]["name"] == "onedark-darker"
    assert set(theme["colors"]) == {
        "Base", "AlertInfo", "AlertWarn", "AlertError", "Annotation",
        "Guidance", "Important", "Title", "Muted"
    }
    PY
    tmux -S "$TMPDIR/tmux.sock" -f ${
      home.xdg.configFile."tmux/tmux.conf".source
    } new-session -d -s validate
    trap 'tmux -S "$TMPDIR/tmux.sock" kill-server || true' EXIT
    tmux -S "$TMPDIR/tmux.sock" list-keys -T root > root.keys
    tmux -S "$TMPDIR/tmux.sock" list-keys -T prefix > prefix.keys
    if grep -E 'M-(h|j|k|l|z|n|p|Tab|[1-9])[[:space:]]' root.keys; then exit 1; fi
    grep -E 'h[[:space:]]+select-pane -L' prefix.keys
    grep -E 'l[[:space:]]+select-pane -R' prefix.keys
    grep -E 'Tab[[:space:]]+last-window' prefix.keys

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
