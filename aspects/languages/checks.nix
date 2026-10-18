{
  pkgs,
  home,
  editorOnly,
}:
let
  check = pkgs.writeText "check-clangd.lua" ''
    local ok, err = xpcall(function()
      local expected = { "clangd", "--background-index", "--clang-tidy" }
      assert(vim.deep_equal(vim.lsp.config.clangd.cmd, expected))
      assert(vim.lsp.is_enabled("clangd"))
      vim.cmd.edit(vim.env.CONTRACT_PROJECT .. "/main.cpp")
      assert(vim.bo.filetype == "cpp", "C++ filetype detection is missing")
      local client
      assert(vim.wait(15000, function()
        client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
        return client and client.initialized
      end, 50), "clangd did not attach")
      assert(client.config.root_dir == vim.env.CONTRACT_PROJECT, "wrong project root")
      local hover = client:request_sync("textDocument/hover", {
        textDocument = { uri = vim.uri_from_bufnr(0) }, position = { line = 0, character = 5 },
      }, 10000, 0)
      assert(hover and hover.result, "clangd returned no hover for main")
      vim.fn.writefile({ vim.json.encode(hover.result) }, vim.env.CONTRACT_RESULT)
    end, debug.traceback)
    if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
    vim.cmd("qa!")
  '';
  noLanguageCheck = pkgs.writeText "check-no-language.lua" ''
    local ok, err = xpcall(function()
      assert(not vim.lsp.is_enabled("clangd"), "an unselected language was enabled")
      assert(vim.fn.executable("clangd") == 0, "an unselected server entered PATH")
    end, debug.traceback)
    if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
    vim.cmd("qa!")
  '';
in
{
  clangd = pkgs.runCommand "language-clangd-runtime" { } ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state"
    export CONTRACT_PROJECT="$TMPDIR/project" CONTRACT_RESULT="$out/hover.json"
    export PATH="${home.home.path}/bin:$PATH"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$CONTRACT_PROJECT" "$out"
    printf 'int main() { return 0; }\n' > "$CONTRACT_PROJECT/main.cpp"
    printf '[{"directory":"%s","arguments":["%s","-std=c++20","-c","main.cpp"],"file":"main.cpp"}]' \
      "$CONTRACT_PROJECT" "${home.home.path}/bin/clang++" > "$CONTRACT_PROJECT/compile_commands.json"
    ${home.home.path}/bin/clang++ -std=c++20 -fsyntax-only "$CONTRACT_PROJECT/main.cpp"
    ${pkgs.neovim-unwrapped}/bin/nvim --headless -u ${
      home.xdg.configFile."nvim/init.lua".source
    } -l ${check}
  '';
  noLanguage = pkgs.runCommand "language-not-selected-runtime" { } ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state"
    export PATH="${editorOnly.home.path}/bin:$PATH"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    ${pkgs.neovim-unwrapped}/bin/nvim --headless -u ${
      editorOnly.xdg.configFile."nvim/init.lua".source
    } -l ${noLanguageCheck}
    touch "$out"
  '';
}
