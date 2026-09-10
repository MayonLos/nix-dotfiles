---
name: nvim-config
description: The nixvim tree at nixvim/ — how a plugin gets added, how lz-n lazy-loading is wired, the keymap/which-key conventions, and the two build settings (combinePlugins, opts vs globalOpts) that silently break things. Use when adding, removing or configuring any Neovim plugin, when editing anything under nixvim/, when a keymap or a :Command does not exist until something else loads, when an option does not apply to the window nvim opened with, or when a plugin's runtime files collide after a rebuild.
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
  `o` Oil, `t` Terminal, `x` Diagnostics, `h` Harpoon, `p` Session.
- Plugin-specific maps live in the plugin's own file; only global editor maps
  belong in `keymappings.nix`.

## Theme

onedark, with the chosen style persisted to
`vim.fn.stdpath("data") .. "/onedark-style"` and re-applied on startup by
`nixvim/theme.nix` (`_G.select_onedark_style` picks one through fzf-lua). A
colorscheme change is therefore runtime state, not a rebuild.

## The plugin set is deliberate

It has been reviewed for redundancy — snacks.nvim already absorbed dressing,
nvim-notify, neoscroll, indent-blankline and vim-illuminate, and the remaining
overlaps (snacks `scope` vs treesitter-textobjects) are documented in the files
themselves. **Do not propose trimming it as cleanup.** The one real debt is
`plugins/editing/multicursors.nix` — upstream is unmaintained; replace it only
when something better exists, not to reduce plugin count.

## Verifying a change

`sudo nixos-rebuild switch --flake .#nixos-btw` (or `nr`) rebuilds the editor.
For an eval-only check of a structural change,
`nix build .#nixosConfigurations.nixos-btw.config.system.build.toplevel`.
Then test in a **fresh** nvim — lazy-loading bugs only reproduce cold.
