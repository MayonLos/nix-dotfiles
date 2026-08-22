{ pkgs, ... }:
{
  extraPlugins = [ pkgs.vimPlugins.friendly-snippets ];

  plugins.luasnip = {
    enable = true;
    fromVscode = [ { } ];
  };

  extraConfigLua = ''
    local ls = require("luasnip")
    local s = ls.snippet
    local t = ls.text_node
    local i = ls.insert_node

    ls.add_snippets("cpp", {
      s("cpt", {
        t({
          "#include <bits/stdc++.h>",
          "using namespace std;",
          "",
          "int main() {",
          "    ios::sync_with_stdio(false);",
          "    cin.tie(nullptr);",
          "",
          "    ",
        }),
        i(0),
        t({ "", "", "    return 0;", "}" }),
      }),
      s("forr", {
        t("for (int "), i(1, "i"), t(" = 0; "), i(2, "i"), t(" < "), i(3, "n"),
        t("; "), i(4, "i"), t("++) {"),
        t({ "", "    " }), i(0), t({ "", "}" }),
      }),
      s("vt", {
        t("vector<"), i(1, "int"), t("> "), i(2, "v"), t("("), i(3, "n"), t(");"), i(0),
      }),
    })
  '';
}
