{
  # Tools nvim launches — language servers, formatters, linters — are declared
  # once in modules/home/programs/dev/toolchain.nix and reach nvim through the
  # profile PATH. Emacs uses the same set, so neither editor can end up on a
  # different nixd or clangd than the other.
  #
  # Consequence, accepted deliberately: this nixvim package is no longer
  # self-contained. `nix run` on it alone yields an editor with no servers.

  # The ruby and python3 remote-plugin hosts are pinned into the closure by
  # default, and this config has no remote plugins at all — the generated
  # rplugin.vim is four empty sections. node and perl were already off; these
  # two were not, and the ruby host alone was 98 MB.
  withRuby = false;
  withPython3 = false;

  # Declaring nothing here does NOT mean nothing is pinned. A nixvim plugin
  # module can declare its own `dependencies`, and `lib/plugins/utils.nix`
  # enables each one with `lib.mkDefault true` — so gitsigns pulls in git,
  # todo-comments pulls in ripgrep and fzf-lua pulls in fzf whether or not this
  # file mentions them. They land in `extraPackages`, which prefixes the
  # wrapper's PATH; nothing interpolates a store path into the config, so the
  # only thing they buy is a self-contained `nix run`.
  #
  # mkDefault means an explicit `false` here wins without mkForce.
  #
  # Measured 2026-09-14 by building one variant per change and comparing the
  # **total** editor closure (individual `path-info -S` values overlap and must
  # not be summed):
  #
  #   baseline                783 MB
  #   git.enable = false      553 MB   -230 MB
  #   ripgrep.enable = false  776 MB     -7 MB
  #   fzf.enable = false      783 MB       0
  #   git + ripgrep           547 MB   -236 MB
  #   ...and fd too           541 MB     -6 MB
  #
  # git alone is 29% of the editor. fzf saves nothing and fd saves 6 MB, so
  # both stay: trading self-containment for zero or near-zero bytes is a pure
  # loss, and fd is what fzf-lua lists files with. git and ripgrep are in the
  # user profile, which is where the editor now finds them.
  dependencies = {
    fd.enable = true;
    git.enable = false;
    ripgrep.enable = false;
  };
}
