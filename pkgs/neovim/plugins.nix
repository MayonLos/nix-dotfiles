{ pkgs }:

let
  inherit (pkgs) vimPlugins;

  configuredPlugins = [
    vimPlugins.blink-cmp
    vimPlugins.codecompanion-nvim
    (vimPlugins.codecompanion-history-nvim.overrideAttrs (_: {
      dependencies = [ vimPlugins.plenary-nvim ];
      doCheck = false;
    }))
    vimPlugins.conform-nvim
    (pkgs.callPackage ../diffview-plus.nix { })
    vimPlugins.flash-nvim
    vimPlugins.fzf-lua
    vimPlugins.gitsigns-nvim
    vimPlugins.grug-far-nvim
    vimPlugins.nvim-lint
    vimPlugins.noice-nvim
    vimPlugins.nvim-autopairs
    vimPlugins.multicursor-nvim
    vimPlugins.nvim-surround
    vimPlugins.nvim-treesitter-context
    vimPlugins.nvim-treesitter-textobjects
    vimPlugins.nvim-ufo
    vimPlugins.nvim-web-devicons
    vimPlugins.which-key-nvim
  ];

  parsers = import ./parsers.nix { inherit pkgs; };
  configured = configuredPlugins ++ [ parsers.plugin ];
  # The LSP setup uses Nixpkgs' pinned nvim-lspconfig server definitions.
  # Keep it in the package graph while matching the baseline's 20 explicit
  # plugin roots (the LSP package is a runtime dependency, not an extra plugin).
  runtimeDependencies = [ vimPlugins.nvim-lspconfig ];
  roots = configured ++ runtimeDependencies;

  # Nixpkgs stores Vim plugin runtime dependencies in passthru.dependencies.
  # Walk that graph explicitly so every plugin and parser/query dependency is
  # present once in the wrapped package's package directory.
  visit =
    seen: pending:
    if pending == [ ] then
      seen
    else
      let
        current = builtins.head pending;
        rest = builtins.tail pending;
        path = current.outPath;
        # `withPlugins` changes nvim-treesitter's passthru dependency graph but
        # leaves its output path unchanged. Always traverse dependencies even
        # when the plugin payload is already present; only deduplicate payloads.
        nextSeen =
          if builtins.elem path (map (plugin: plugin.outPath) seen) then seen else seen ++ [ current ];
      in
      visit nextSeen ((current.dependencies or [ ]) ++ rest);

  plugins = visit [ ] roots;
in
{
  inherit
    configured
    plugins
    parsers
    runtimeDependencies
    ;
}
