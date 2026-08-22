{
  plugins.dial.enable = true;

  extraConfigLua = ''
    local augend = require("dial.augend")
    require("dial.config").augends:register_group({
      default = {
        augend.integer.alias.decimal,
        augend.integer.alias.hex,
        augend.constant.alias.bool,
        augend.date.alias["%Y/%m/%d"],
        augend.date.alias["%Y-%m-%d"],
        augend.semver.alias.semver,
      },
    })
  '';

  keymaps =
    let
      manip = dir: mode: {
        action.__raw = "function() require('dial.map').manipulate('${dir}', '${mode}') end";
      };
    in
    [
      (
        {
          mode = "n";
          key = "<C-a>";
          options.desc = "Increment";
        }
        // manip "increment" "normal"
      )
      (
        {
          mode = "n";
          key = "<C-x>";
          options.desc = "Decrement";
        }
        // manip "decrement" "normal"
      )
      (
        {
          mode = "v";
          key = "<C-a>";
          options.desc = "Increment";
        }
        // manip "increment" "visual"
      )
      (
        {
          mode = "v";
          key = "<C-x>";
          options.desc = "Decrement";
        }
        // manip "decrement" "visual"
      )
      (
        {
          mode = "v";
          key = "g<C-a>";
          options.desc = "Increment (cumulative)";
        }
        // manip "increment" "gvisual"
      )
      (
        {
          mode = "v";
          key = "g<C-x>";
          options.desc = "Decrement (cumulative)";
        }
        // manip "decrement" "gvisual"
      )
    ];
}
