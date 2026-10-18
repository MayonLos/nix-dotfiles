{ lib, ... }:
let
  data = import ./data.nix;
  tools = {
    docker = pkgs: [ pkgs.dockerfile-language-server ];
    nix = pkgs: [
      pkgs.nixd
      pkgs.nixfmt
    ];
    lua = pkgs: [
      pkgs.lua-language-server
      pkgs.lua54Packages.luacheck
      pkgs.stylua
    ];
    python = pkgs: [
      pkgs.pyright
      pkgs.ruff
    ];
    java = pkgs: [
      pkgs.jdt-language-server
      pkgs.google-java-format
    ];
    shell = pkgs: [
      pkgs.bash-language-server
      pkgs.shfmt
      pkgs.shellcheck
    ];
    latex = pkgs: [ pkgs.texlab ];
    markdown = pkgs: [ pkgs.marksman ];
    matlab = pkgs: [ pkgs.matlab-language-server ];
    cmake = pkgs: [ pkgs.cmake-language-server ];
    web = pkgs: [
      pkgs.nodejs
      pkgs.typescript-language-server
      pkgs.vscode-langservers-extracted
    ];
    yaml = pkgs: [ pkgs.yaml-language-server ];
  };
  modules = {
    lua = [ ./lua-tools.nix ];
    python = [ ./python-tools.nix ];
    java = [ ./java-tools.nix ];
    latex = [ ./latex-tools.nix ];
    matlab = [ ./matlab/home.nix ];
  };
in
{
  den.aspects = lib.mapAttrs' (
    id: packages:
    lib.nameValuePair "${id}-support" {
      editorLanguages = [ data.${id} ];
      homeManager = { pkgs, ... }: {
        imports = modules.${id} or [ ];
        home.packages = packages pkgs;
      };
    }
  ) tools;
}
