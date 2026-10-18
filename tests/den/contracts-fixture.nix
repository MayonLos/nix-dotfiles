{
  inputs,
  lib,
  ...
}:
{
  imports = [
    "${inputs.appearance}/default.nix"
    "${inputs.default-tools}/default.nix"
    "${inputs.languages}/default.nix"
  ];

  # Small real consumers for contract acceptance; not replacements for the
  # existing rich desktop/editor configuration.
  den.aspects.sample-kitty = { user, ... }: {
    homeManager = {
      imports = [ (import "${inputs.appearance}/kitty.nix" { palette = user.appearance; }) ];
      programs.kitty.enable = true;
    };
  };
  den.aspects.sample-neovim = { user, ... }: {
    homeManager = { editorLanguages, ... }: {
      imports = [
        (import "${inputs.appearance}/neovim.nix" { palette = user.appearance; })
        (import "${inputs.languages}/neovim.nix" { contributions = editorLanguages; })
      ];
      programs.neovim.enable = true;
    };
  };
  den.aspects.sample-gui-apps.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.firefox
      pkgs.thunar
      pkgs.vscode-fhs
    ];
  };
  den.aspects.sample-repeat-cpp.editorLanguages = [ (import "${inputs.languages}/cpp-data.nix") ];
  den.aspects.sample-conflicting-cpp.editorLanguages = [
    (lib.recursiveUpdate (import "${inputs.languages}/cpp-data.nix") {
      neovim.servers.clangd.cmd = [ "incompatible-clangd" ];
    })
  ];
}
