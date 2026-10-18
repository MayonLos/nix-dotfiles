{ pkgs }:

let
  configDir = ../../config/nvim;
  # The runtime needs only the Lua tree, not the entire flake source closure.
  configPath = builtins.path {
    path = configDir;
    name = "nvim-config";
  };
  pluginSet = import ./plugins.nix { inherit pkgs; };
  editorTools = with pkgs; [
    file
    tree-sitter
    fd
    fzf
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
