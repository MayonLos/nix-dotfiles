{ pkgs, ... }:
{
  extraPlugins = [ pkgs.vimPlugins.mcphub-nvim ];

  extraConfigLua = ''
    require("mcphub").setup({
      cmd = "${pkgs.mcp-hub}/bin/mcp-hub",
      use_bundled_binary = false,
      auto_approve = false,
    })
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>am";
      action = "<cmd>MCPHub<cr>";
      options.desc = "MCPHub: open UI";
    }
  ];
}
