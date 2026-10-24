{ pkgs, appearance, ... }:
let
  contributions =
    builtins.attrValues
      (import ../languages/contract.nix { inherit (pkgs) lib; }).defaults;
  acpAdapters = {
    codex = "${pkgs.local.codex-acp}/bin/codex-acp";
    claude = "${pkgs.local.claude-agent-acp}/bin/claude-agent-acp";
  };
  neovim = import ./package.nix {
    inherit pkgs contributions acpAdapters;
    palette = appearance;
  };
  reduced = import ./package.nix {
    inherit pkgs contributions acpAdapters;
    palette = appearance // {
      reducedMotion = true;
    };
  };
in
{
  neovim =
    pkgs.runCommand "neovim-checks"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.lua-language-server
          pkgs.vscode-langservers-extracted
          pkgs.stylua
          pkgs.clang-tools
          pkgs.basedpyright
          pkgs.taplo
          pkgs.marksman
          pkgs.nixd
          pkgs.nixfmt
          pkgs.ruff
          pkgs.lua54Packages.luacheck
        ];
      }
      ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export XDG_CONFIG_HOME="$TMPDIR/config"
            export XDG_DATA_HOME="$TMPDIR/data"
            export XDG_STATE_HOME="$TMPDIR/state"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            export NVIM_APPNAME=nvim
            unset VIMINIT
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
            for test in startup completion integration workflow fileops lua_workspace modern interface ai native codediff; do
              export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
              ${neovim.normal}/bin/nvim --headless -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            export NVIM_TEST_FILE="${neovim.configDir}/tests/samples.lua"
            for sample in lua cpp python toml markdown nix; do
              NVIM_SAMPLE="$sample" ${neovim.normal}/bin/nvim --headless -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            export NVIM_LSP_INTEGRATION=1
            for test in lsp; do
              export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
              ${neovim.normal}/bin/nvim --clean --headless \
                -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            export NVIM_TEST_FILE="${neovim.configDir}/tests/wrapper.lua"
            NVIM_CHECK_MODE=reduced ${reduced.normal}/bin/nvim --headless \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            NVIM_CHECK_MODE=dev NVIM_EXPECTED_CONFIG_DIR=${./config} \
              NVIM_CONFIG_DIR=${./config} ${neovim.dev}/bin/nvim --headless \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            NVIM_CHECK_MODE=normal NVIM_CONFIG_DIR=/invalid-config ${neovim.normal}/bin/nvim --headless \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            echo 'error("expected failure")' > "$TMPDIR/failure.lua"
            if NVIM_TEST_FILE="$TMPDIR/failure.lua" ${neovim.normal}/bin/nvim --headless \
              -c 'luafile ${neovim.configDir}/tests/run.lua' > "$TMPDIR/failure.log" 2>&1; then
              echo "failed assertion was swallowed"
              exit 1
            fi
        touch "$out"
      '';
}
