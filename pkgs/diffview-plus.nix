# Package expressions live at the repo root rather than under modules/ because
# lib/import-dir.nix imports every .nix file there as a Home Manager module.
# Same reason as pkgs/libtexprintf.nix -- see the comment there.
#
# sindrets/diffview.nvim last pushed 2024-08-02 and nixpkgs pins 2024-06-13;
# this fork last pushed 2026-09-08, with 686 commits against the original's 312
# (all checked 2026-09-14).
#
# It is an override of the nixpkgs package rather than a fresh buildVimPlugin
# call: buildVimPlugin runs a require check over every Lua module, and ~30 of
# diffview's only load after its bootstrap has set the DiffviewGlobal global.
# nixpkgs already carries the skip list for those; writing the derivation from
# scratch loses it and the build fails with "attempt to index global
# 'DiffviewGlobal' (a nil value)".
{ vimPlugins, fetchFromGitHub }:
vimPlugins.diffview-nvim.overrideAttrs (old: {
  version = "0-unstable-2026-09-08";
  src = fetchFromGitHub {
    owner = "dlyongemallo";
    repo = "diffview.nvim";
    rev = "be86a001f13b4d307814bd6e06eac429a2777ae8";
    hash = "sha256-NoIX2kid3Hfb/LExxSXYGllG0/5/mY7NYT5jzx0DqBw=";
  };

  # The fork adds VCS adapters (p4, jj, null), pinned two-way layouts and a
  # selection store, none of which existed when nixpkgs wrote its list. Every
  # name here was taken from the failing build's own "Failed to require
  # module:" lines, not guessed.
  nvimSkipModules = (old.nvimSkipModules or [ ]) ++ [
    "diffview.scene.layouts.diff_2_hor_pinned"
    "diffview.scene.layouts.diff_2_ver_pinned"
    "diffview.scene.layouts.diff_4_mixed"
    "diffview.scene.views.diff.file_diff_view"
    "diffview.scene.views.diff.file_dir_diff_view"
    "diffview.scene.views.diff.file_merge_view"
    "diffview.scene.views.diff.null_diff_view"
    "diffview.scene.window"
    "diffview.selection_store"
    "diffview.vcs.adapters.jj.init"
    "diffview.vcs.adapters.null.init"
    "diffview.vcs.adapters.p4.init"
  ];

  meta = old.meta // {
    description = "Maintained fork of diffview.nvim: single-tabpage diffs and file history";
    homepage = "https://github.com/dlyongemallo/diffview.nvim";
  };
})
