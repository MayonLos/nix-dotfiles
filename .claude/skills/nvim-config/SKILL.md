---
name: nvim-config
description: The nixvim tree at nixvim/ — how a plugin gets added, how lz-n lazy-loading is wired, the keymap/which-key conventions, the build settings (combinePlugins, opts vs globalOpts) that silently break things, and the four ways a setting here can evaluate cleanly yet never reach the runtime. Use when adding, removing or configuring any Neovim plugin, when editing anything under nixvim/, when a keymap or a :Command does not exist until something else loads, when an option does not apply to the window nvim opened with, when a plugin's runtime files collide after a rebuild, when a setting looks correct but the editor behaves as if it were absent, when only the first buffer of a session misbehaves, when folding is empty right after opening a file, when something else owns vim.ui.input/select or a highlight group, when hand-packaging a Vim plugin with buildVimPlugin or overrideAttrs, or when you need to verify a change without a full nixos-rebuild.
---

# Neovim (nixvim)

`nixvim/` in the repo root, built by `modules/home/programs/dev/nvim.nix`, which
is the single bridge. It lives outside `modules/` because `importDir` would load
each of its ~70 files as a broken Home Manager module — see the `nix-modules`
skill.

`nvim.nix` instantiates a **second** nixpkgs carrying one overlay
(`mcp-hub`, not in nixpkgs). That is deliberate: an overlay on the shared `pkgs`
would rebuild everything downstream of stdenv for the sake of one editor.

## Imports here are explicit — the opposite of modules/

`importDir` does not reach this tree. Every file is listed by hand:

```
nixvim/default.nix         → core, options, keymappings, autocmds, highlights, theme, plugins, packages
nixvim/plugins/default.nix → one line per category directory
nixvim/plugins/<cat>/default.nix → one line per plugin file
```

**A new plugin file that is not added to its category's `default.nix` is simply
not loaded, and nothing errors.** That is the most common way a change here does
nothing. Categories: `completion lsp formatting navigation appearance editing ai
debug git terminal utility`.

## Adding a plugin

1. `nixvim/plugins/<category>/<name>.nix`, then add it to that directory's
   `default.nix`.
2. Enable it. `plugins.<name> = { enable = true; settings = { … }; }` when
   nixvim has a module for it; otherwise `extraPlugins = [ pkgs.vimPlugins.<pkg> ];`
   plus an `extraConfigLua` block (heirline, mcphub, friendly-snippets and
   codecompanion-history go this route).
3. Lazy-load it — see below.
4. Bind it: `keymaps` entries with `options.desc`, and a `<leader>` group in
   `plugins/utility/which-key.nix` if it opens a new prefix.

Language servers, formatters and linters are **not** declared here. They go in
`modules/home/programs/dev/toolchain.nix`, and a `cmd` in
`nixvim/plugins/lsp/servers.nix` names a bare binary — never a store path. The
`dev-toolchain` skill has the closure numbers behind that rule.

## lz-n: every trigger the keymaps reach must be declared

`plugins.lz-n.enable` is on (`nixvim/core/lz.nix`); most plugin files carry
`lazyLoad.settings.{event,ft,cmd,keys}`. Anything that is not needed at startup
should.

lz-n creates a **stub per declared trigger** and loads the plugin when a stub
fires. A command left off `cmd` does not exist until something unrelated happens
to load the plugin. codecompanion is the worked example: only the three headline
commands were listed, so `<leader>at`, `<leader>aT` and `<leader>ax` died with
`E492: Not an editor command` on a cold start while working fine after a chat had
been opened. Check with `vim.fn.exists(":TheCommand")` in a fresh nvim, not in
the one you have been testing in.

Same trap in `keys`: a key bound in `keymaps` but absent from `lazyLoad` fires
against a plugin that has not loaded.

## combinePlugins: plugins that ship runtime files must be standalone

`nixvim/core/performance.nix` merges every plugin into one pack directory, which
is what keeps `runtimepath` short. Plugins shipping their own
`queries/`/`ftplugin/` collide in that merged directory and one silently wins.
`standalonePlugins` currently holds nvim-treesitter, snacks.nvim (its
`queries/markdown/injections.scm` collided with treesitter's), blink.cmp,
codecompanion.nvim and mcphub.nvim.

If a new plugin misbehaves only after a rebuild — missing queries, a highlight
that never applies, a filetype plugin that does not run — add it there before
debugging the plugin itself.

`byteCompileLua` is on for configs, plugins, the nvim runtime and the Lua
library. It is a startup-time win with no config surface; leave it alone.

## opts, never globalOpts

`nixvim/options.nix` uses `opts` (`vim.opt`). `globalOpts` (`vim.opt_global`)
sets only the global *default*, which window- and buffer-local options copy at
creation time — and the startup window and buffer both exist before `init.lua`
runs. Using it meant `number`, `relativenumber`, `cursorline`, `list` and
`signcolumn` never applied to the window `nvim file` actually opened.

## Keymap conventions

- `options.desc` on every mapping — which-key renders it, and an undescribed
  mapping shows up as a blank row.
- Lua callbacks go through `action.__raw = ''function() … end''`.
- Leader groups are registered in `plugins/utility/which-key.nix` with
  `__unkeyed-1`: `f` Find, `s` Search, `g` Git, `l` LSP, `d` Debug, `w` Window,
  `u` Utility/Toggle, `a` AI (`ac` CLI agent), `b` Buffer, `c` Code, `n` Docs,
  `t` Terminal, `x` Diagnostics, `h` Harpoon, `p` Session, `m` Multicursor.
  There is no `o` group: it was oil's, and oil was removed on 2026-09-18 —
  snacks' explorer on `<leader>e` is the only file manager now.
- Plugin-specific maps live in the plugin's own file; only global editor maps
  belong in `keymappings.nix`.

## Theme

**tokyonight** — the same scheme the whole host wears (see the two-tier colour
rule in `desktop-apps`). The style (`night` / `storm` / `moon` / `day`) is
persisted to `vim.fn.stdpath("data") .. "/tokyonight-style"` and re-applied on
startup by `nixvim/theme.nix`; `_G.select_tokyonight_style`, on `<leader>fs`,
picks one through fzf-lua. A colorscheme change is runtime state, not a rebuild.

Two traps live in that file and both were measured, not guessed:

- `tokyonight.setup{}` **replaces** the option table rather than merging, so
  passing only `style` throws away `styles.floats`/`styles.sidebars =
  "transparent"` from `plugins/appearance/colorscheme.nix`.
- `tokyonight.load()` does **not** fire Neovim's `ColorScheme` event, and
  `nixvim/highlights.nix` hangs its entire override table off that event.

So the switcher merges onto `require("tokyonight.config").options` and goes
through `vim.cmd.colorscheme`, which does fire it. Change either half back and
every override in `highlights.nix` silently disappears for the rest of the
session — and on every later start, because the choice is persisted.

## The plugin set is deliberate

It has been reviewed for redundancy — snacks.nvim already absorbed dressing,
nvim-notify, neoscroll, indent-blankline and vim-illuminate, and the remaining
overlaps (snacks `scope` vs treesitter-textobjects) are documented in the files
themselves. **Do not propose trimming it as cleanup.**

The multicursors debt is settled: `plugins/editing/multicursors.nix` now wires
jake-stewart's `multicursor.nvim` by hand (nixvim has no module for it), which
also dropped hydra.nvim. Neovim merged built-in multiple cursors upstream
(neovim/neovim#41587) but 0.12.4 ships neither `:MultiCursor` nor its help, so
the plugin stays until that lands.

`nvim-treesitter` was archived upstream on 2026-04-03 and the pinned version is
that day's commit. Highlighting, folding and treesitter-context all still work
on 0.12.4, so there is nothing to do here — the migration to the `main` branch
is nixvim's to make, not this repo's. Do not start it locally.

## Enabling a thing is not wiring it — four ways this config lied

Every one of these had correct-looking Nix, evaluated fine, produced no error,
and did the wrong thing at runtime. They are the same bug wearing four hats:
**the setting lands somewhere real, but too late or in the wrong object.** None
were findable by reading the config; all were found by driving the built editor
and watching what it actually did.

- **A config key that only the plugin's own `setup` reads, when lz-n defers
  that setup.** `render-markdown`'s `latex.converter` pointed at a wrapper
  script, and the *first* markdown buffer of every session still used the
  default converter — `plugin/render-markdown.lua` runs `setup(vim.g.
  render_markdown_config)` when lz-n finally sources the plugin directory, and
  the manager renders immediately, so the render context captured a buffer
  config built from defaults. `custom_handlers` is read live off a module field
  and was therefore already ours, which is why only one key looked stale. Worse,
  that plugin caches converter output globally by formula text, so one bad early
  pass outlived the race for the whole session. Fixed by also setting
  `vim.g.render_markdown_config` — the plugin's own answer to plugin-manager
  ordering. **If a plugin offers a `vim.g.*_config` global, prefer it over
  trusting setup ordering.**

- **An `enabled = true` that only writes a config table.** `snacks.input`
  never claimed `vim.ui.input`; snacks auto-starts only the modules in its own
  `events` table. Measured: `vim.ui.input` resolved to
  `runtime/lua/vim/ui.lua` before an explicit `Snacks.input.enable()` and to
  `snacks/input.lua` after. The same mechanism is why `terminal` in
  `snacks.nix` documents that its `enabled` key is never read. **For any snacks
  module, check `debug.getinfo` on what it claims to own, not the config
  table.**

- **A synchronous provider replaced by an asynchronous one.** `nvim-ufo`
  computes fold ranges asynchronously; turning off treesitter's `foldexpr` and
  forcing `foldmethod=manual` globally left buffers with *no* folds for ~2s
  after opening — `zc` returned `E490: No fold found`. foldexpr is kept on as
  the pre-attach provider; ufo switches the window to manual itself once it has
  ranges (its README: "foldmethod option will finally become manual if ufo is
  working"). **Never force `foldmethod` globally for ufo.**

- **`overrideAttrs` that changes a version but not a name.** `buildVimPlugin`
  computes `name` from `pname`/`version` before the override runs, so
  `pkgs/diffview-plus.nix` produced the fork's source under a store path still
  spelling the old upstream date. Contents right, label wrong, and the label is
  what an audit reads. Override `name` explicitly. While there: overriding the
  nixpkgs package rather than writing a fresh `buildVimPlugin` is what inherits
  `nvimSkipModules`, without which diffview fails its require check on ~30
  modules that need its bootstrap global.

The lesson is in `## Verifying a change` below, and it is not optional: a
config change to this tree is unverified until a freshly built binary has been
driven and observed.

## Verifying a change

`sudo nixos-rebuild switch --flake .#nixos-btw` (or `nr`) rebuilds the editor.
For an eval-only check of a structural change,
`nix build .#nixosConfigurations.nixos-btw.config.system.build.toplevel`.
Then test in a **fresh** nvim — lazy-loading bugs only reproduce cold.

Building just the editor is much faster than a rebuild and needs no sudo:

```nix
nix build --no-link --print-out-paths --impure --expr '
let
  f = builtins.getFlake "git+file:///home/mayon/nix-dotfiles?dirty=1";
  system = "x86_64-linux";
  nvimPkgs = import f.inputs.nixpkgs { inherit system; config.allowUnfree = true;
    overlays = [ (_: _: { mcp-hub = f.inputs.mcp-hub.packages.${system}.default; }) ]; };
in f.inputs.nixvim.legacyPackages.${system}.makeNixvimWithModule {
  pkgs = nvimPkgs; module = import /home/mayon/nix-dotfiles/nixvim;
}'
```

Then, against that binary:

- **Startup errors**, which nothing else surfaces:
  `nvim --headless -c 'lua vim.wait(3000); local m=vim.split(vim.fn.execute("messages"),"\n") …' -c 'qa!'`
- **What a key or command actually resolves to**: `vim.fn.maparg(lhs, mode,
  false, true)` — note `nvim_get_keymap` returns `<leader>` already expanded to
  a literal space, so looking up the string `"<leader>x"` always fails.
- **Who owns a `vim.ui.*` or a highlight**: `debug.getinfo(fn, "S").short_src`
  and `nvim_get_hl(0, { name = …, link = false })`.
- **What the editor actually draws**, including virtual text, folds and CJK
  alignment — run it in tmux and read the screen back as text:

  ```sh
  tmux new-session -d -s v -x 160 -y 48 "<store-path>/bin/nvim <file>"
  sleep 6; tmux send-keys -t v <keys>; sleep 3
  tmux capture-pane -t v -p          # add -e to inspect colour codes
  tmux kill-session -t v
  ```

- **Which subprocesses a plugin spawns**, when a converter or external tool is
  involved: wrap `vim.system` in a `-c luafile` probe and print every call. That
  is what exposed the render-markdown converter race; no amount of reading found
  it.
