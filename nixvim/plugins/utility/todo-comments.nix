{
  plugins.todo-comments = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings = {
        event = [
          "BufReadPost"
          "BufNewFile"
        ];
        cmd = [
          "TodoFzfLua"
          "TodoQuickFix"
          "TodoLocList"
        ];
      };
    };
    settings.signs = true;
  };

  keymaps = [
    {
      mode = "n";
      key = "]t";
      action.__raw = "function() require('todo-comments').jump_next() end";
      options.desc = "Next todo comment";
    }
    {
      mode = "n";
      key = "[t";
      action.__raw = "function() require('todo-comments').jump_prev() end";
      options.desc = "Prev todo comment";
    }
    {
      mode = "n";
      key = "<leader>ft";
      action = "<cmd>TodoFzfLua<cr>";
      options.desc = "Find todos";
    }
  ];
}
