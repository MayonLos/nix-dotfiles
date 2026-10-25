{
  pkgs,
  palette,
  contributions,
  acpAdapters ? { },
  nixOptions ? null,
}:

let
  sourceConfig = ./config;
  # Keep stable plugins' Lua packages on one LuaJIT ABI/environment. This only
  # selects the wrapper's Lua dependency set, preserving the upstream editor.
  editor = pkgs.unstable.neovim-unwrapped // {
    lua = pkgs.luajit;
  };
  languages = (import ../languages/contract.nix { inherit (pkgs) lib; }).collect contributions;
  debugTools = import ./debug-tools.nix { inherit pkgs; };
  dataRuntime = pkgs.writeTextDir "lua/mayon/generated.lua" (
    "return "
    + pkgs.lib.generators.toLua { } {
      inherit palette;
      nix_options = nixOptions;
      parser_runtime = pluginSet.parserRuntime;
      ansi = import ../../appearance/appearance/ansi.nix palette;
      tools = debugTools.tools // {
        copilot = "${pkgs.copilot-language-server}/bin/copilot-language-server";
        sqlite3 = "${pkgs.lib.getLib pkgs.sqlite}/lib/libsqlite3.so";
        codex_acp = acpAdapters.codex or "";
        claude_acp = acpAdapters.claude or "";
      };
      versions = debugTools.versions // {
        codecompanion = pkgs.unstable.codecompanion-nvim.version;
        copilot = pkgs.copilot-language-server.version;
        codediff = pkgs.vimPlugins.codediff-nvim.version;
      };
      plugin_dependencies = pluginSet.dependencyMap;
      startup_plugins = pluginSet.startupNames;
      languages = { inherit (languages) servers formatters linters; };
    }
  );
  configPath = pkgs.runCommand "nvim-config" { } ''
    mkdir -p "$out"
    cp -R ${sourceConfig}/. "$out/"
    chmod -R u+w "$out"
    cp ${dataRuntime}/lua/mayon/generated.lua "$out/lua/mayon/generated.lua"
    # Resolve the pinned One Dark adapter once at build time, then ship LuaJIT
    # bytecode with this exact palette and editor. Dev configs fall back to the
    # live adapter; no user cache or runtime download is needed.
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cat > "$TMPDIR/compile.lua" <<'LUA'
    vim.opt.runtimepath:prepend(vim.env.MAYON_THEME_PLUGIN)
    vim.opt.runtimepath:prepend(vim.env.MAYON_THEME_CONFIG)
    vim.g.mayon_compile_theme = true
    local original = vim.api.nvim_get_hl(0, {})
    require("mayon.ui.theme").setup()
    local highlights = {}
    for name, value in pairs(vim.api.nvim_get_hl(0, {})) do
      if not vim.deep_equal(value, original[name]) then highlights[name] = value end
    end
    local source = "return " .. vim.inspect(highlights)
    local chunk = assert(loadstring(source))
    local file = assert(io.open(vim.env.MAYON_THEME_CONFIG .. "/lua/mayon/generated_highlights.lua", "wb"))
    file:write(string.dump(chunk, true))
    file:close()
    LUA
    MAYON_THEME_PLUGIN=${pkgs.vimPlugins.onedark-nvim} MAYON_THEME_CONFIG="$out" \
      ${pkgs.unstable.neovim-unwrapped}/bin/nvim --headless -u NONE -i NONE -n \
      -c "luafile $TMPDIR/compile.lua" -c 'qa!'
    test -s "$out/lua/mayon/generated_highlights.lua"

  '';
  pluginSet = import ./plugins.nix { inherit pkgs; };
  editorTools = with pkgs; [
    file
    curl
    tree-sitter
    fd
    ripgrep
    lazygit
    yazi
    trash-cli
    nodejs
    tmux
    procps
    lsof
    wl-clipboard
    sqlite
  ];

  mkNeovim =
    { development }:
    pkgs.wrapNeovimUnstable editor {
      extraName = if development then "-dev" else "";

      inherit (pluginSet) plugins;

      # Wrapper VIMINIT sources the same init.lua that Home Manager links at
      # ~/.config/nvim/init.lua. The config tree itself owns global idempotence
      # for callers that reach it through another Neovim entry point.
      luaRcContent = ''
        local config_dir = vim.env.NVIM_CONFIG_DIR or "${configPath}"
        vim.opt.runtimepath:prepend("${dataRuntime}")
        vim.opt.runtimepath:append(require("mayon.generated").parser_runtime)
        vim.opt.runtimepath:prepend(config_dir)
        vim.opt.runtimepath:append(config_dir .. "/after")
        dofile(config_dir .. "/init.lua")
      '';

      withRuby = false;
      withPython3 = false;
      withNodeJs = false;
      withPerl = false;

      wrapperArgs =
        (
          if development then
            [
              "--set-default"
              "NVIM_CONFIG_DIR"
              configPath
            ]
          else
            [
              "--set"
              "NVIM_CONFIG_DIR"
              configPath
            ]
        )
        ++ [
          # 0.12 probes OSC 11 + DSR before --cmd/user config and blocks the
          # first frame. This editor fixes dark/truecolor explicitly and owns
          # a non-blocking OSC 11 lifecycle, so the native probe is redundant.
          "--set-default"
          "NVIM_NOTTYFAST"
          "1"
          "--prefix"
          "PATH"
          ":"
          (pkgs.lib.makeBinPath editorTools)
        ];
    };
in
{
  configDir = configPath;
  normal = mkNeovim { development = false; };
  dev = mkNeovim { development = true; };
}
