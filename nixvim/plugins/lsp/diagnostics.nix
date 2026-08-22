{
  diagnostic.settings = {
    virtual_text = false;
    virtual_lines = true;

    signs.text.__raw = ''
      {
        [vim.diagnostic.severity.ERROR] = "󰅚 ",
        [vim.diagnostic.severity.WARN]  = "󰀪 ",
        [vim.diagnostic.severity.INFO]  = "󰋽 ",
        [vim.diagnostic.severity.HINT]  = "󰌶 ",
      }
    '';
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>ll";
      action.__raw = ''
        function()
          local enabled = vim.diagnostic.config().virtual_lines
          vim.diagnostic.config({ virtual_lines = not enabled })
        end
      '';
      options.desc = "Toggle diagnostic virtual lines";
    }
  ];
}
