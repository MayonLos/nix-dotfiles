_: {
  perSystem =
    { pkgs, ... }:
    let
      neovim = import ../aspects/editing/neovim/package.nix { inherit pkgs; };
    in
    {
      packages.neovim = neovim.normal;
      packages.neovim-dev = neovim.dev;

      checks.neovim =
        pkgs.runCommand "neovim-checks"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.vscode-langservers-extracted
              pkgs.stylua
            ];
          }
          ''
                export XDG_CONFIG_HOME="$TMPDIR/config"
                export XDG_DATA_HOME="$TMPDIR/data"
                export XDG_STATE_HOME="$TMPDIR/state"
                export XDG_CACHE_HOME="$TMPDIR/cache"
                export NVIM_APPNAME=nvim
                unset VIMINIT
                mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
                for test in startup completion integration; do
                  export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
                  ${neovim.normal}/bin/nvim --headless -c 'luafile ${neovim.configDir}/tests/run.lua'
                done
                export NVIM_LSP_INTEGRATION=1
                for test in native statusline tabline breadcrumbs lsp; do
                  export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
                  ${neovim.normal}/bin/nvim --clean --headless \
                    -c 'luafile ${neovim.configDir}/tests/run.lua'
                done
                NVIM_CONFIG_DIR=${../aspects/editing/neovim/config} ${neovim.dev}/bin/nvim --headless \
              -c "lua assert(vim.g.colors_name == 'onedark-darker'); assert(require('mayon.generated').languages.servers.clangd)" -c 'qa!'
            NVIM_CONFIG_DIR=/invalid-config ${neovim.normal}/bin/nvim --headless \
              -c "lua assert(vim.env.NVIM_CONFIG_DIR ~= '/invalid-config'); assert(vim.g.colors_name == 'onedark-darker')" -c 'qa!'
            touch "$out"
          '';
    };
}
