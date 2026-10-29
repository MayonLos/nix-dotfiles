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
          pkgs.texlab
          pkgs.texliveFull
          pkgs.ruff
          pkgs.typescript-language-server
          pkgs.yaml-language-server
          pkgs.bash-language-server
          pkgs.cmake-language-server
          pkgs.shfmt
          pkgs.shellcheck
          pkgs.cmake
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
            if NVIM_TEST_FILE="${neovim.configDir}/tests/selfcheck_failure.lua" \
              ${neovim.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_capture.lua' \
              -c 'luafile ${neovim.configDir}/tests/run.lua' > "$TMPDIR/selfcheck-failure.log" 2>&1; then
              echo "selfcheck swallowed an injected runtime error"
              exit 1
            fi
            grep -q SELFCHECK_INJECTION_OBSERVED "$TMPDIR/selfcheck-failure.log"
            grep -q 'captured runtime ERROR' "$TMPDIR/selfcheck-failure.log"
            mkdir -p "$TMPDIR/startup-project"
            printf 'int main(void) { return 0; }\n' > "$TMPDIR/startup-project/main.c"
            (
              cd "$TMPDIR/startup-project"
              for scenario in empty file directory session-save session-restore pipe help; do
                args=()
                case "$scenario" in
                  file|session-save) args=(main.c) ;;
                  directory) args=(.) ;;
                  pipe) args=(-) ;;
                  help) args=("+help help") ;;
                esac
                printf 'pipe fixture\n' | NVIM_STARTUP_CASE="$scenario" \
                  NVIM_TEST_FILE="${neovim.configDir}/tests/selfcheck_startup.lua" \
                  ${neovim.normal}/bin/nvim --headless \
                  --cmd 'luafile ${neovim.configDir}/tests/selfcheck_capture.lua' \
                  --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
                  "''${args[@]}" -c 'luafile ${neovim.configDir}/tests/run.lua'
                ${pkgs.jq}/bin/jq -e '[.events[] | select(.level >= 4)] | length == 0' "$XDG_STATE_HOME/nvim/selfcheck.json"
              done
            )
            # Capture errors before VIMINIT, including lazy setup and scheduled
            # callbacks. Keep all observations and LSP logs in this sandbox.
            for test in selfcheck_log selfcheck selfcheck_actions outline_race session_tools; do
              NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua" \
                ${neovim.normal}/bin/nvim --headless \
                --cmd 'luafile ${neovim.configDir}/tests/selfcheck_capture.lua' \
                --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
                -c 'luafile ${neovim.configDir}/tests/run.lua'
              ${pkgs.jq}/bin/jq -e '[.events[] | select(.level >= 4)] | length == 0' "$XDG_STATE_HOME/nvim/selfcheck.json"
            done
            for sample in tsx ts c h nix lua md py json yaml sh make cmake; do
              NVIM_SAMPLE="$sample" NVIM_TEST_FILE="${neovim.configDir}/tests/selfcheck_languages.lua" \
                ${neovim.normal}/bin/nvim --headless \
                --cmd 'luafile ${neovim.configDir}/tests/selfcheck_capture.lua' \
                --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
                -c 'luafile ${neovim.configDir}/tests/run.lua'
              ${pkgs.jq}/bin/jq -e '[.events[] | select(.level >= 4)] | length == 0' "$XDG_STATE_HOME/nvim/selfcheck.json"
            done
            # Round 44 exercises the document workbench, responsive outline,
            # same-canvas float surfaces and native completion before integrations.
            for test in overhaul startup completion completion_ui integration workflow document_workbench fileops lua_workspace modern interface ai native codediff panels_picker panels_ai panels_aux panels_surface picker_lsp embedded refinement runtime_smoke debug debug_gdb java_debug keymap_discovery; do
              export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
              ${neovim.normal}/bin/nvim --headless --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            # Passing a file on argv is a different lazy-loading path from :edit.
            printf 'int main(void) { return 0; }\n' > "$TMPDIR/workbench-startup.c"
            NVIM_TEST_FILE="${neovim.configDir}/tests/document_startup.lua" ${neovim.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
              "$TMPDIR/workbench-startup.c" -c 'luafile ${neovim.configDir}/tests/run.lua'
            export NVIM_TEST_FILE="${neovim.configDir}/tests/samples.lua"
            for sample in lua cpp python toml markdown nix tex rust go; do
              NVIM_SAMPLE="$sample" ${neovim.normal}/bin/nvim --headless --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            export NVIM_LSP_INTEGRATION=1
            for test in lsp; do
              export NVIM_TEST_FILE="${neovim.configDir}/tests/$test.lua"
              ${neovim.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
                -c 'luafile ${neovim.configDir}/tests/run.lua'
            done
            export NVIM_TEST_FILE="${neovim.configDir}/tests/wrapper.lua"
            NVIM_CHECK_MODE=reduced ${reduced.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            NVIM_CHECK_MODE=dev NVIM_EXPECTED_CONFIG_DIR=${./config} \
              NVIM_CONFIG_DIR=${./config} ${neovim.dev}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            NVIM_CHECK_MODE=normal NVIM_CONFIG_DIR=/invalid-config ${neovim.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
              -c 'luafile ${neovim.configDir}/tests/run.lua'
            echo 'error("expected failure")' > "$TMPDIR/failure.lua"
            if NVIM_TEST_FILE="$TMPDIR/failure.lua" ${neovim.normal}/bin/nvim --headless \
              --cmd 'luafile ${neovim.configDir}/tests/selfcheck_offline.lua' \
              -c 'luafile ${neovim.configDir}/tests/run.lua' > "$TMPDIR/failure.log" 2>&1; then
              echo "failed assertion was swallowed"
              exit 1
            fi
        touch "$out"
      '';
}
