# Terminal

Installs Kitty and renders its configuration from `user.appearance`, including the shared ANSI palette and reduced-motion preference. Selecting this aspect makes Kitty configuration a complete managed file; Noctalia is not a second Kitty template writer.

Owned files are `default.nix` and `kitty.nix`, both private. The output is the Kitty package and `kitty/kitty.conf`. Removing the aspect removes those declarations in the next generation; Kitty scrollback files and other user data remain intact.
