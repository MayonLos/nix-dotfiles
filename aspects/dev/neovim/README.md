# Neovim

Installs the repository's Neovim build and generates its runtime data from an explicit palette and selected `editorLanguages` contributions. Selecting an appearance is required for the rich renderer. Language contributions are consumed only when this editor aspect is selected.

`package.nix` is a public parameterized package factory. Callers must provide `pkgs`, `palette`, and `contributions`; it returns the editor packages and private configuration output. `config/` is private and may be used only by this feature's package and checks. `checks.nix` is a public feature test hook using `{ pkgs, lib, system, nixos, home, appearance }` as needed. `default.nix` is the public registration entry; `plugins.nix` and `parsers.nix` are private.

The output includes the Neovim package and generated Lua data for palette/ANSI values, language servers, formatters, linters, and plugin dependencies. The flake package export is built through the same factory with explicit default data.

Removing the aspect removes the package and managed `nvim/init.lua` link after activation. It preserves user projects, editor histories, plugin state and any files outside the managed link; no project files are rewritten.
