{ den, ... }: {
  imports = [ ../../appearance/appearance ];
  den.aspects = {
    neovim = { user, host, ... }: {
      homeManager =
        { pkgs, editorLanguages, ... }:
        let
          editor = import ./package.nix {
            inherit pkgs;
            palette = user.appearance;
            nixOptions = {
              flake = user.flakePath;
              host = host.name;
            };
            contributions = editorLanguages;
          };
        in
        {
          home.packages = [
            editor.normal
            pkgs.trash-cli
          ];
          xdg.configFile."nvim/init.lua".source = "${editor.configDir}/init.lua";
          assertions = [
            {
              assertion = user.appearance != null;
              message = "Select an appearance for the rich Neovim renderer";
            }
          ];
        };
    };
  };
}
