{
  plugins.treesitter-textobjects = {
    enable = true;
    settings = {
      select.lookahead = true;
      move.set_jumps = true;
    };
  };

  keymaps =
    let
      sel =
        obj:
        ''function() require("nvim-treesitter-textobjects.select").select_textobject("${obj}", "textobjects") end'';
      gns =
        obj:
        ''function() require("nvim-treesitter-textobjects.move").goto_next_start("${obj}", "textobjects") end'';
      gps =
        obj:
        ''function() require("nvim-treesitter-textobjects.move").goto_previous_start("${obj}", "textobjects") end'';
      gne =
        obj:
        ''function() require("nvim-treesitter-textobjects.move").goto_next_end("${obj}", "textobjects") end'';
      gpe =
        obj:
        ''function() require("nvim-treesitter-textobjects.move").goto_previous_end("${obj}", "textobjects") end'';
    in
    [
      {
        mode = [
          "x"
          "o"
        ];
        key = "af";
        action.__raw = sel "@function.outer";
        options.desc = "Select function (outer)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "if";
        action.__raw = sel "@function.inner";
        options.desc = "Select function (inner)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "ac";
        action.__raw = sel "@class.outer";
        options.desc = "Select class (outer)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "ic";
        action.__raw = sel "@class.inner";
        options.desc = "Select class (inner)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "aa";
        action.__raw = sel "@parameter.outer";
        options.desc = "Select parameter (outer)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "ia";
        action.__raw = sel "@parameter.inner";
        options.desc = "Select parameter (inner)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "al";
        action.__raw = sel "@loop.outer";
        options.desc = "Select loop (outer)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "il";
        action.__raw = sel "@loop.inner";
        options.desc = "Select loop (inner)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "ai";
        action.__raw = sel "@conditional.outer";
        options.desc = "Select conditional (outer)";
      }
      {
        mode = [
          "x"
          "o"
        ];
        key = "ii";
        action.__raw = sel "@conditional.inner";
        options.desc = "Select conditional (inner)";
      }

      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "]m";
        action.__raw = gns "@function.outer";
        options.desc = "Next function start";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "[m";
        action.__raw = gps "@function.outer";
        options.desc = "Prev function start";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "]M";
        action.__raw = gne "@function.outer";
        options.desc = "Next function end";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "[M";
        action.__raw = gpe "@function.outer";
        options.desc = "Prev function end";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "]]";
        action.__raw = gns "@class.outer";
        options.desc = "Next class start";
      }
      {
        mode = [
          "n"
          "x"
          "o"
        ];
        key = "[[";
        action.__raw = gps "@class.outer";
        options.desc = "Prev class start";
      }

      {
        mode = "n";
        key = "<leader>sn";
        action.__raw = ''function() require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner") end'';
        options.desc = "Swap parameter with next";
      }
      {
        mode = "n";
        key = "<leader>sp";
        action.__raw = ''function() require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner") end'';
        options.desc = "Swap parameter with prev";
      }
    ];
}
