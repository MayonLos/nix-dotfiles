{
  pkgs,
  home,
  palette,
}:
let
  kittyScript = pkgs.writeText "check-kitty-palette.py" ''
    import json
    import os
    from kitty.config import load_config
    bad = []
    options = load_config("${home.xdg.configFile."kitty/kitty.conf".source}", accumulate_bad_lines=bad)
    # Kitty embeds optimized Python: `assert` statements are stripped.
    if bad:
        raise RuntimeError(repr(bad))
    expected = ${
      builtins.toJSON {
        background = palette.bg;
        foreground = palette.fg;
        color0 = palette.black;
        color1 = palette.red;
        color15 = palette.brightFg;
      }
    }
    for key, value in expected.items():
        if getattr(options, key).as_sharp != value:
            raise RuntimeError(f"Kitty palette mismatch: {key}")
    with open(os.environ["PALETTE_RESULT"], "w") as result:
        json.dump({"background": options.background.as_sharp, "foreground": options.foreground.as_sharp}, result)
  '';
  luaCheck = pkgs.writeText "check-neovim-palette.lua" ''
    local ok, err = xpcall(function()
      assert(vim.g.colors_name == "${palette.name}")
      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      assert(normal.bg == tonumber("${pkgs.lib.removePrefix "#" palette.bg}", 16))
      assert(normal.fg == tonumber("${pkgs.lib.removePrefix "#" palette.fg}", 16))
      assert(vim.g.terminal_color_0 == "${palette.black}")
      assert(vim.g.terminal_color_1 == "${palette.red}")
      assert(vim.g.terminal_color_15 == "${palette.brightFg}")
    end, debug.traceback)
    if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
    vim.cmd("qa!")
  '';
in
{
  kitty = pkgs.runCommand "appearance-kitty-runtime" { } ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache"
    export PALETTE_RESULT="$out/kitty.json"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$out"
    ${pkgs.kitty}/bin/kitty +runpy "exec(open('${kittyScript}').read())"
    if [ ! -s "$PALETTE_RESULT" ]; then
      echo 'Kitty palette validation did not complete' >&2
      exit 1
    fi
  '';
  neovim = pkgs.runCommand "appearance-neovim-runtime" { } ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    ${pkgs.neovim-unwrapped}/bin/nvim --headless -u ${
      home.xdg.configFile."nvim/init.lua".source
    } -l ${luaCheck}
    touch "$out"
  '';
}
