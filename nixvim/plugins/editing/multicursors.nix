{ pkgs, lib, ... }:
let
  plugin = pkgs.vimPlugins.multicursor-nvim;

  # Every binding is n+x: the match commands seed themselves from the word under
  # the cursor in normal mode and from the selection in visual mode, so limiting
  # them to one mode throws away half the plugin.
  key = k: fn: desc: {
    __unkeyed-1 = "<leader>m${k}";
    __unkeyed-2.__raw = ''function() require("multicursor-nvim").${fn} end'';
    mode = [
      "n"
      "x"
    ];
    inherit desc;
  };
in
{
  # smoka7/multicursors.nvim last pushed 2025-02-26 (19 months); jake-stewart's
  # last pushed 2026-03-24 (both checked 2026-09-14). Replacing it also drops
  # hydra.nvim, which was in this closure only as smoka7's dependency.
  #
  # Neovim merged built-in multiple cursors (neovim/neovim#41587), but 0.12.4
  # has neither `:MultiCursor` nor `:help multicursor` -- verified on the build
  # this config produces -- so the plugin is still the only option here.
  extraPlugins = [
    {
      inherit plugin;
      optional = true;
    }
  ];

  # No nixvim module exists for it, so lz-n loads it by its runtimepath name on
  # first use of any key below.
  plugins.lz-n.plugins = [
    {
      __unkeyed-1 = lib.getName plugin;
      after = ''
        function()
          local mc = require("multicursor-nvim")
          mc.setup()

          -- A keymap layer is only live while more than one cursor exists, so
          -- these can reuse keys that mean something else the rest of the time.
          -- Without it there is no way to dismiss the cursors with <esc> or to
          -- move the main cursor, which is most of what makes the plugin usable.
          mc.addKeymapLayer(function(layer)
            layer({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Previous cursor" })
            layer({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Next cursor" })
            layer({ "n", "x" }, "<leader>mx", mc.deleteCursor, { desc = "Delete main cursor" })
            layer("n", "<esc>", function()
              if mc.cursorsEnabled() then
                mc.clearCursors()
              else
                mc.enableCursors()
              end
            end, { desc = "Clear cursors" })
          end)
        end
      '';
      keys = [
        (key "n" "matchAddCursor(1)" "Add cursor at next match")
        (key "N" "matchAddCursor(-1)" "Add cursor at previous match")
        (key "s" "matchSkipCursor(1)" "Skip next match")
        (key "S" "matchSkipCursor(-1)" "Skip previous match")
        (key "j" "lineAddCursor(1)" "Add cursor on line below")
        (key "k" "lineAddCursor(-1)" "Add cursor on line above")
        (key "a" "matchAllAddCursors()" "Add cursor to every match in buffer")
        (key "t" "toggleCursor()" "Disable / re-enable cursors")
        (key "q" "clearCursors()" "Clear cursors")
        {
          # An operator, so it takes a motion: <leader>mgip puts a cursor on
          # every line of the paragraph. It cannot go through `key` above,
          # which wraps its argument in a call.
          __unkeyed-1 = "<leader>mg";
          __unkeyed-2.__raw = ''function() require("multicursor-nvim").addCursorOperator() end'';
          mode = [
            "n"
            "x"
          ];
          desc = "Add cursor over motion";
        }
      ];
    }
  ];
}
