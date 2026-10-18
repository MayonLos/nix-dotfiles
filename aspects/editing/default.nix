{ den, ... }: {
  den.aspects = {
    neovim = { user, ... }: {
      homeManager =
        { pkgs, editorLanguages, ... }:
        let
          editor = import ./neovim/package.nix {
            inherit pkgs;
            palette = user.appearance;
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
    vscode = { host, ... }: {
      homeManager.imports = [ ./vscode.nix ];
      provides.${host.name}.includes = [ den.aspects.editing-runtime ];
    };
    jetbrains = { host, ... }: {
      homeManager.imports = [ ./jetbrains.nix ];
      provides.${host.name}.includes = [ den.aspects.editing-runtime ];
    };
    editing-runtime.nixos.imports = [ ./host.nix ];
  };
}
