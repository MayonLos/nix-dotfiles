{
  pkgs,
  palette,
  contributions,
}:

let
  sourceConfig = ./config;
  languages = (import ../languages/contract.nix { inherit (pkgs) lib; }).collect contributions;
  dataRuntime = pkgs.writeTextDir "lua/mayon/generated.lua" (
    "return "
    + pkgs.lib.generators.toLua { } {
      inherit palette;
      ansi = import ../../appearance/appearance/ansi.nix palette;
      tools = {
        sqlite3 = "${pkgs.lib.getLib pkgs.sqlite}/lib/libsqlite3.so";
        lldb_dap = "${pkgs.llvmPackages.lldb}/bin/lldb-dap";
        debugpy_python = "${pkgs.python3.withPackages (ps: [ ps.debugpy ])}/bin/python3";
      };
      plugin_dependencies = pluginSet.dependencyMap;
      languages = { inherit (languages) servers formatters linters; };
    }
  );
  configPath = pkgs.runCommand "nvim-config" { } ''
    mkdir -p "$out"
    cp -R ${sourceConfig}/. "$out/"
    chmod -R u+w "$out"
    cp ${dataRuntime}/lua/mayon/generated.lua "$out/lua/mayon/generated.lua"
  '';
  pluginSet = import ./plugins.nix { inherit pkgs; };
  editorTools = with pkgs; [
    file
    tree-sitter
    fd
    ripgrep
    lazygit
    yazi
    trash-cli
    wl-clipboard
  ];

  mkNeovim =
    { development }:
    pkgs.wrapNeovimUnstable pkgs.neovim-unwrapped {
      extraName = if development then "-dev" else "";

      inherit (pluginSet) plugins;

      # Wrapper VIMINIT sources the same init.lua that Home Manager links at
      # ~/.config/nvim/init.lua. The config tree itself owns global idempotence
      # for callers that reach it through another Neovim entry point.
      luaRcContent = ''
        local config_dir = vim.env.NVIM_CONFIG_DIR or "${configPath}"
        vim.opt.runtimepath:prepend("${dataRuntime}")
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
