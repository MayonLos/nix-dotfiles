{ pkgs }:

let
  inherit (pkgs) vimPlugins;

  configuredPlugins = [
    vimPlugins.lz-n
    vimPlugins.oil-nvim
    vimPlugins.yazi-nvim
    vimPlugins.nvim-dap
    vimPlugins.nvim-dap-view
    vimPlugins.nvim-dap-virtual-text
    vimPlugins.overseer-nvim
    vimPlugins.todo-comments-nvim
    vimPlugins.rainbow-delimiters-nvim
    vimPlugins.nvim-colorizer-lua
    vimPlugins.tiny-inline-diagnostic-nvim
    vimPlugins.satellite-nvim
    vimPlugins.incline-nvim
    vimPlugins.smear-cursor-nvim
    vimPlugins.blink-cmp
    vimPlugins.codecompanion-nvim
    (vimPlugins.codecompanion-history-nvim.overrideAttrs (_: {
      dependencies = [ vimPlugins.plenary-nvim ];
      doCheck = false;
    }))
    vimPlugins.conform-nvim
    (pkgs.callPackage ./diffview-plus.nix { })
    vimPlugins.flash-nvim
    vimPlugins.gitsigns-nvim
    vimPlugins.grug-far-nvim
    vimPlugins.heirline-nvim
    vimPlugins.lazydev-nvim
    vimPlugins.nvim-lint
    vimPlugins.nvim-navic
    vimPlugins.noice-nvim
    vimPlugins.nvim-autopairs
    vimPlugins.multicursor-nvim
    vimPlugins.nvim-surround
    vimPlugins.nvim-treesitter-context
    vimPlugins.nvim-treesitter-textobjects
    vimPlugins.nvim-web-devicons
    vimPlugins.onedark-nvim
    vimPlugins.render-markdown-nvim
    vimPlugins.snacks-nvim
    vimPlugins.trouble-nvim
    vimPlugins.which-key-nvim
  ];

  parsers = import ./parsers.nix { inherit pkgs; };
  configured = configuredPlugins ++ [ parsers.plugin ];
  # The LSP setup uses Nixpkgs' pinned nvim-lspconfig server definitions.
  # Server definitions are a runtime dependency of the language contribution
  # consumer, independent of the visual plugins above.
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

  closure = visit [ ] roots;
  startup = with vimPlugins; [
    lz-n
    onedark-nvim
    heirline-nvim
    snacks-nvim
    nvim-web-devicons
  ];
  # List the complete closure explicitly as optional too: nixpkgs otherwise
  # promotes dependencies of optional roots into start/. Parsers and queries
  # remain available through the same generated dependency graph.
  plugins = map (plugin: {
    inherit plugin;
    optional = !(builtins.elem plugin.outPath (map (p: p.outPath) startup));
  }) closure;
  dependencyMap =
    builtins.listToAttrs (
      map (plugin: {
        name = pkgs.lib.getName plugin;
        value = map (dep: pkgs.lib.getName dep) (plugin.dependencies or [ ]);
      }) closure
    )
    // {
      "nvim-treesitter" = map (dep: pkgs.lib.getName dep) parsers.plugin.dependencies;
    };
in
{
  inherit
    configured
    plugins
    parsers
    runtimeDependencies
    dependencyMap
    ;
}
