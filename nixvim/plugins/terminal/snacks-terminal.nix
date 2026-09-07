_: {
  # Keymaps for snacks.terminal, which replaced toggleterm (unmaintained since
  # 2025-03). Window defaults live in ../appearance/snacks.nix; only bindings
  # are here, because plugins.snacks.settings is one attrset and splitting it
  # across files would collide.
  #
  # Snacks.terminal.toggle keys its instances on cmd + opts (see M.tid in
  # snacks/terminal.lua), so <C-\> and <leader>tf pass identical arguments on
  # purpose: they must toggle the *same* float, the way toggleterm's `toggle(1,
  # ...)` reused terminal id 1. <leader>th passes a different position and so
  # gets its own instance -- that is a real behaviour change from toggleterm,
  # where switching direction moved one terminal instead of opening a second.
  keymaps =
    let
      float = ''function() require("snacks").terminal.toggle() end'';
      bottom = ''
        function()
          require("snacks").terminal.toggle(nil, { win = { position = "bottom", height = 15 } })
        end
      '';
      mkTerm = mode: key: code: desc: {
        inherit mode key;
        action.__raw = code;
        options = {
          silent = true;
          inherit desc;
        };
      };
    in
    [
      (mkTerm [ "n" "t" ] "<C-\\>" float "Toggle Terminal")
      (mkTerm "n" "<leader>tf" float "Float Terminal")
      (mkTerm "n" "<leader>th" bottom "Bottom Terminal")

      # Window navigation straight out of terminal mode. These were in
      # toggleterm.nix but never depended on it -- they are plain terminal-mode
      # mappings, so they outlive the plugin swap unchanged.
      {
        mode = "t";
        key = "<C-h>";
        action = "<cmd>wincmd h<cr>";
        options = {
          silent = true;
          desc = "Terminal: left window";
        };
      }
      {
        mode = "t";
        key = "<C-j>";
        action = "<cmd>wincmd j<cr>";
        options = {
          silent = true;
          desc = "Terminal: lower window";
        };
      }
      {
        mode = "t";
        key = "<C-k>";
        action = "<cmd>wincmd k<cr>";
        options = {
          silent = true;
          desc = "Terminal: upper window";
        };
      }
      {
        mode = "t";
        key = "<C-l>";
        action = "<cmd>wincmd l<cr>";
        options = {
          silent = true;
          desc = "Terminal: right window";
        };
      }
      # snacks' own terminal style binds a double-<esc> for this (its
      # `term_normal` key), but only inside snacks terminal buffers. Keeping the
      # global mapping means :terminal buffers behave the same way.
      {
        mode = "t";
        key = "<Esc><Esc>";
        action = "<C-\\><C-n>";
        options = {
          silent = true;
          desc = "Terminal: normal mode";
        };
      }
    ];
}
