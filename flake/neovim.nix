_: {
  perSystem =
    { pkgs, ... }:
    let
      neovim = import ../pkgs/neovim { inherit pkgs; };
    in
    {
      packages.neovim = neovim.normal;
      packages.neovim-dev = neovim.dev;

      checks.neovim = pkgs.runCommand "neovim-checks" { nativeBuildInputs = [ pkgs.git ]; } ''
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        export NVIM_APPNAME=nvim
        unset VIMINIT
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
        for test in startup completion; do
          export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
          ${neovim.normal}/bin/nvim --headless -c 'luafile ${neovim.configDir}/tests/run.lua'
        done
        for test in native statusline tabline breadcrumbs lsp; do
          export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
          ${neovim.normal}/bin/nvim --clean --headless \
            -c 'luafile ${neovim.configDir}/tests/run.lua'
        done
        touch "$out"
      '';
    };
}
