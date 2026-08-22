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

  # Only `fd` is still worth declaring here: it is what fzf-lua shells out to
  # for file listing and it is the one tool in this list not already in the
  # user profile. bat, git, ripgrep and fzf are all in profile PATH already, and
  # nixvim only ever adds these to the wrapper's PATH — it does not interpolate
  # store paths into the config (verified against the generated init.lua), so
  # declaring them again just pinned another copy into nvim's closure.
  dependencies.fd.enable = true;
}
