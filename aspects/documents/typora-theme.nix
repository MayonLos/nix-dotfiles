{
  pkgs,
  ...
}:

# Typora "Claude" theme (blaxisomu/typora_claude) -- CSS only, no AI plugin.
#
# Upstream README: drop claude.css, claude-dark.css and the claude-fonts/
# directory into Typora's theme folder. Verified against the pinned tree below:
# the two .css files sit at the archive root and their @font-face rules load
# fonts through the relative url("./claude-fonts/..."), so the directory has to
# stay a sibling of the .css files rather than a separate fontconfig install.
#
# This only stages the files. Typora keeps its own Preferences (conf.user.json)
# in the same config directory and rewrites the theme selection from the GUI,
# so the theme is deliberately not selected here -- pick "Claude" / "Claude
# Dark" from Typora's Themes menu after the first launch.
#
# The files are linked out of the store, one target at a time, instead of
# symlinking the whole themes directory: Typora's bundled themes and anything
# dropped there by hand stay ordinary writable files in a writable directory.
let
  src = pkgs.fetchFromGitHub {
    owner = "blaxisomu";
    repo = "typora_claude";
    rev = "76ebf79bf205a9c110586b3653dd6d1432ac2e91";
    hash = "sha256-ASChhENwVbAuJsJsdi2WxlNhQvaWHNOuEFa9UO/HAIU=";
  };
in
{
  xdg.configFile."Typora/themes/claude.css".source = "${src}/claude.css";
  xdg.configFile."Typora/themes/claude-dark.css".source = "${src}/claude-dark.css";
  xdg.configFile."Typora/themes/claude-fonts".source = "${src}/claude-fonts";
}
