_: {
  perSystem =
    { pkgs, ... }:
    let
      palette = import ../aspects/appearance/appearance/onedark-darker.nix;
      contributions =
        builtins.attrValues
          (import ../aspects/dev/languages/contract.nix { inherit (pkgs) lib; }).defaults;
      neovim = import ../aspects/dev/neovim/package.nix { inherit pkgs palette contributions; };
    in
    {
      packages.neovim = neovim.normal;
      packages.neovim-dev = neovim.dev;
    };
}
