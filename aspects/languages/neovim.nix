{ contributions }:
{ lib, ... }:
let
  collected = (import ./contract.nix { inherit lib; }).collect contributions;
in
{
  programs.neovim.initLua = ''
    do
      local servers = ${lib.generators.toLua { } collected.servers}
      for name, settings in pairs(servers) do
        vim.lsp.config(name, settings)
        vim.lsp.enable(name)
      end
    end
  '';
}
