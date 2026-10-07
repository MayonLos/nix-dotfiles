# Nixvim runtime traps and focused probes

Read this when a setting evaluates but Neovim behaves as if it were absent, a
plugin works only after another action, or a rebuild changes plugin behavior.

## Lazy loading

lz-n creates trigger stubs only for declared `cmd`, `keys`, `event`, and `ft`
entries. A missing command trigger can produce `E492` on a cold start while the
same command works after opening a related feature. A keymap not represented in
`lazyLoad.settings.keys` can fire before its plugin is loaded. In a fresh editor,
check commands with `vim.fn.exists(":Command")` and inspect mappings with
`vim.fn.maparg(lhs, mode, false, true)`.

DAP, goto-preview, bqf, smear-cursor and rainbow-delimiters were removed
at the user's request to simplify the editor. Use native LSP jumps and Trouble
for location lists. Do not restore debug key groups or the DAP-only highlight
without restoring an explicitly requested debugging workflow.

`mini.align` (`ga`/`gA`) and `mini.splitjoin` (`gS`) share the lazily loaded
mini.nvim package. Keep both normal and visual modes in their key triggers;
the first keypress must load the generated module setups and replay into the
new mappings. Probe `VjgA=<CR>` on two assignment lines and `gS` twice on an
argument list in separate fresh sessions.

## Merged plugin runtime files

`combinePlugins` merges most plugins into one pack directory. If a plugin ships
queries or filetype runtime files, inspect for path collisions and add it to
`standalonePlugins` when needed. Current standalone entries include
nvim-treesitter, snacks.nvim, blink.cmp, codecompanion.nvim, and mcphub.nvim.
For example, snacks' markdown injection query collided with Treesitter's.

## Configuration timing and ownership

- Some plugins read `vim.g.<name>_config` when sourced; a late `setup()` can
  occur after the plugin has already initialized its buffer state. Prefer the
  plugin's documented global config when lazy loading exposes an ordering race.
- A module's `enabled = true` may only populate its options. For snacks modules,
  verify the implementation actually owns the target function or UI API after
  loading; `debug.getinfo(fn, "S").short_src` identifies the active provider.
- ufo computes folds asynchronously. Keep a synchronous fold provider available
  until ufo attaches; globally forcing `foldmethod=manual` leaves a period with
  no folds.
- `tokyonight.setup` replaces its option table. Merge style changes with
  `require("tokyonight.config").options`; use `vim.cmd.colorscheme` so
  `ColorScheme` fires and `highlights.nix` reapplies its overrides.
- In `pkgs/diffview-plus.nix`, retain the existing package override's
  `nvimSkipModules`; a fresh buildVimPlugin can fail require checks before
  bootstrap. When overriding a version, inspect the computed package name too.

## Building versus evaluating

An evaluation check does not compile a derivation. The repository's known
full-system build command is:

```sh
nix build .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

For faster runtime checks, build the editor with the pinned Nixvim and the
`mcp-hub` overlay as done by `modules/home/programs/dev/nvim.nix`. The project
has previously used this exact standalone build expression:

```sh
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

Then use the resulting binary, not the currently installed editor:

- Startup errors: inspect `:messages` after a short wait in headless Neovim.
- Effective mapping: `vim.fn.maparg(lhs, mode, false, true)`; `<leader>` is
  expanded in the returned mapping.
- UI/highlight owner: `debug.getinfo(fn, "S").short_src` or
  `nvim_get_hl(0, { name = "…", link = false })`.
- Drawn output: run in tmux and inspect with `tmux capture-pane -p`.
- External commands: wrap `vim.system` in a probe and record invoked commands.

When a built binary cannot be exercised, report the check as build-only rather
than runtime-verified.
