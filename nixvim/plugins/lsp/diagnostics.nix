{
  diagnostic.settings = {
    virtual_text = false;

    # Only under the cursor. A markdown note whose index links to pages that do
    # not exist yet drew a full-width virtual line per link -- a dozen of them
    # on one screen, pushing the actual prose apart. The sign column still marks
    # every line, and <leader>ll below switches back to showing them all.
    virtual_lines.current_line = true;

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
          local all = vim.diagnostic.config().virtual_lines == true
          vim.diagnostic.config({ virtual_lines = all and { current_line = true } or true })
        end
      '';
      options.desc = "Toggle diagnostic virtual lines (current line / all)";
    }
  ];
}
