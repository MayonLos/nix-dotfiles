---
name: nvim-config
description: 修改 nixvim/ 的插件、延迟加载、键位、选项和 Neovim 包覆盖；排查求值成功但编辑器运行行为不符。
---

# Neovim / Nixvim

The configuration lives in root `nixvim/`, bridged into Home Manager by
`modules/home/programs/dev/nvim.nix`. It stays outside `modules/`: the latter
is recursively imported as Home Manager modules.

## Wiring a plugin

- Imports in `nixvim/` are explicit. Add a new file to its category's
  `default.nix`; otherwise it is silently unused. The category is imported by
  `plugins/default.nix`.
- Prefer a Nixvim module when available. For a hand-wired plugin, declare it
  in `extraPlugins` and configure it in Lua. Lazy-load non-startup plugins.
- Every command or mapping that is meant to trigger lazy loading must be in
  that plugin's `lazyLoad.settings.cmd` or `keys`. Check all commands reached
  by keymaps, including secondary commands, in a fresh Neovim session.
- `lazyLoad.settings.before`/`after` map to lz.n's hooks, but for Neovim
  plugins they **replace** Nixvim's generated code: `after` replaces the
  `setup()` call, `before` replaces the generated `vim.g` injection. Only set
  them when you reproduce that work yourself; vim plugins (no setup) are safe.
  Prefer `keys`/`cmd` triggers over manual `trigger_load` where possible.
- Put plugin-specific maps beside the plugin. Global editor maps belong in
  `keymappings.nix`; every map needs `options.desc`. Register new leader groups
  in `plugins/utility/which-key.nix`.
- Servers, formatters, and linters belong in
  `modules/home/programs/dev/toolchain.nix`; see the `dev-toolchain` skill.
  LSP `cmd` values are bare executable names so the editor does not pin those
  tools into its own closure.

## Runtime invariants

- `core/performance.nix` combines plugin runtime files. Plugins shipping
  `queries/`, `ftplugin/`, or similar files that collide must be listed in
  `standalonePlugins`.
- Use `opts` for editor options that must apply to the window and buffer opened
  at startup. `globalOpts` only changes defaults copied when later windows or
  buffers are created.
- Keep the Tokyo Night style switcher merging the live setup options and
  applying through `:colorscheme`; highlights are re-applied on the
  `ColorScheme` event. See [runtime traps](references/runtime-traps.md) for
  why these details matter and how to probe them.
- Do not trim the plugin set as generic cleanup: known overlaps and removed
  plugins have already been reviewed in their modules.

## Verification

Nix evaluation only checks configuration evaluation; it does not build the
editor or prove runtime behavior. For runtime-sensitive changes, build the
Nixvim package using the repository's pinned inputs, then drive that binary in
a **fresh** session. Lazy-loading and startup ordering bugs can disappear after
another action loads the plugin. Use the focused probes in
[runtime traps](references/runtime-traps.md); do not claim runtime verification
from evaluation alone.
