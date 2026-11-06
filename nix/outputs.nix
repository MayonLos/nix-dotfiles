_: {
  perSystem =
    { pkgs, ... }:
    let
      palette = import ../aspects/appearance/appearance/onedark.nix;
      contributions =
        builtins.attrValues
          (import ../aspects/dev/languages/contract.nix { inherit (pkgs) lib; }).defaults;
      acpAdapters = {
        claude = "${pkgs.local.claude-agent-acp}/bin/claude-agent-acp";
      };
      neovim = import ../aspects/dev/neovim/package.nix {
        inherit
          pkgs
          palette
          contributions
          acpAdapters
          ;
      };
    in
    {
      packages.neovim = neovim.normal;
      packages.neovim-dev = neovim.dev;
    };
}
