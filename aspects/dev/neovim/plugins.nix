{ pkgs }:

let
  inherit (pkgs) vimPlugins;

  configuredPlugins = [
    vimPlugins.lz-n
    vimPlugins.oil-nvim
    vimPlugins.yazi-nvim
    vimPlugins.todo-comments-nvim
    (vimPlugins.rainbow-delimiters-nvim.overrideAttrs (old: {
      # Upstream 0.12 health returns before its default-config report, so 0.12
      # treats a valid Lua setup as an empty/error health report.
      postPatch = (old.postPatch or "") + ''
        substituteInPlace lua/rainbow-delimiters/health.lua \
          --replace-fail 'function M.check()' 'function M.check() start("Rainbow delimiters"); ok("Plugin loaded; default or Lua setup is supported")'
      '';
    }))
    vimPlugins.nvim-highlight-colors
    vimPlugins.tiny-glimmer-nvim
    vimPlugins.tiny-inline-diagnostic-nvim
    vimPlugins.satellite-nvim
    # unstable: stable 19.13 缺少 ACP 修复；当前 20.0.1 已核对 interactions/inline/ACP API
    (pkgs.unstable.codecompanion-nvim.overrideAttrs (_: {
      # Keep the runtime graph on the editor's stable LuaJIT/Plenary. Mixing
      # unstable Plenary would introduce a second LuaJIT into the wrapper env.
      dependencies = [ vimPlugins.plenary-nvim ];
    }))
    vimPlugins.claudecode-nvim
    (vimPlugins.sidekick-nvim.overrideAttrs (old: {
      # Switching native inline completion to DeepSeek/off also disables NES.
      # Sidekick's CLI remains usable without a Copilot client in that state.
      postPatch = (old.postPatch or "") + ''
        substituteInPlace lua/sidekick/health.lua \
          --replace-fail '  if not found then' '  if not found and (Config.nes.enabled == false or vim.g.sidekick_nes == false) then vim.health.info("Copilot NES disabled; no Copilot LSP required") elseif not found then'
      '';
    }))
    vimPlugins.minuet-ai-nvim
    vimPlugins.mini-diff
    vimPlugins.edgy-nvim
    vimPlugins.smart-splits-nvim
    (vimPlugins.codecompanion-history-nvim.overrideAttrs (_: {
      dependencies = [ vimPlugins.plenary-nvim ];
      doCheck = false;
    }))
    vimPlugins.conform-nvim
    vimPlugins.codediff-nvim
    vimPlugins.flash-nvim
    vimPlugins.gitsigns-nvim
    vimPlugins.grug-far-nvim
    vimPlugins.heirline-nvim
    vimPlugins.lazydev-nvim
    vimPlugins.nvim-lint
    vimPlugins.nvim-dap
    vimPlugins.nvim-dap-view
    vimPlugins.nvim-dap-virtual-text
    vimPlugins.one-small-step-for-vimkind
    vimPlugins.nvim-jdtls
    vimPlugins.aerial-nvim
    vimPlugins.neogit
    vimPlugins.nvim-autopairs
    vimPlugins.multicursor-nvim
    vimPlugins.nvim-surround
    vimPlugins.nvim-treesitter-context
    vimPlugins.nvim-treesitter-textobjects
    vimPlugins.nvim-web-devicons
    vimPlugins.onedark-nvim
    vimPlugins.render-markdown-nvim
    (vimPlugins.snacks-nvim.overrideAttrs (old: {
      # LSP responses must enter the finder coroutine before its time-budget yield.
      patches = (old.patches or [ ]) ++ [ ./patches/snacks-lsp-coroutine.patch ];
      # Pinned 2.31 checks mmdc unconditionally. Make the disabled capability
      # explicit in rendering and health rather than installing Chromium/mmdc.
      postPatch = (old.postPatch or "") + ''
        # The pinned nvim-treesitter has no norg grammar. Disable only that
        # unsupported document-image integration; M.langs() discovers queries.
        test -f queries/norg/images.scm
        rm queries/norg/images.scm
        substituteInPlace lua/snacks/image/init.lua \
          --replace-fail 'if Snacks.health.have_tool("mmdc") then' 'if M.config.mermaid and M.config.mermaid.enabled == false then Snacks.health.info("Mermaid rendering disabled by configuration") elseif Snacks.health.have_tool("mmdc") then'
        substituteInPlace lua/snacks/image/doc.lua \
          --replace-fail 'if not Snacks.image.config.math.enabled and img.type == "math" then' 'if (img.type == "chart" and Snacks.image.config.mermaid and Snacks.image.config.mermaid.enabled == false) or (not Snacks.image.config.math.enabled and img.type == "math") then'
        # A resize may already be queued when the narrow layout closes a picker.
        # The closed picker releases preview/layout; skip its stale callback.
        substituteInPlace lua/snacks/picker/core/picker.lua \
          --replace-fail '      self:set_layout(Snacks.picker.config.layout(self.opts))' '      if not self.closed then self:set_layout(Snacks.picker.config.layout(self.opts)) end'
        # The finder can finish after close replaced its task with Async.nop().
        # Do not resume a matcher that has already been released.
        substituteInPlace lua/snacks/picker/core/finder.lua \
          --replace-fail '    finder(function(item)' '    finder(function(item) if picker.closed then return end' \
          --replace-fail '    if not self.task:aborted() then' '    if not self.task:aborted() and not picker.closed then'
        # A queued resize can still reach a list after close released its picker.
        substituteInPlace lua/snacks/picker/core/list.lua \
          --replace-fail 'function M:render()' 'function M:render() if not self.picker or self.picker.closed then return end' \
          --replace-fail 'function M:update_cursorline()' 'function M:update_cursorline() if not self.picker or self.picker.closed then return end'
        substituteInPlace lua/snacks/dashboard.lua \
          --replace-fail 'if M.status.did_setup then' 'if not M.status.did_setup then M.setup() end; if M.status.did_setup then'
      '';
    }))
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
  startup =
    with vimPlugins;
    [
      lz-n
      onedark-nvim
    ]
    ++ builtins.filter (p: pkgs.lib.getName p == "snacks.nvim") configuredPlugins;
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
  # Publish only parser/query resources on one startup runtimepath entry.
  # Keep plugin scripts optional while avoiding scans of dozens of roots.
  parserRuntime = [
    (pkgs.buildEnv {
      name = "nvim-parser-runtime";
      paths = parsers.plugin.dependencies;
      pathsToLink = [
        "/parser"
        "/queries"
      ];
    }).outPath
  ];
  startupNames = map pkgs.lib.getName startup;
}
