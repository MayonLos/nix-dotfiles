{ pkgs, ... }:

{
  # Single source of truth for the tools an *editor* starts: language servers,
  # formatters and linters. Both nvim (nixvim/) and Emacs
  # (programs/dev/emacs/) reach these through the profile PATH, so neither can
  # drift onto a different nixd or clangd than the other.
  #
  # Compilers, interpreters and build tools deliberately stay in their own
  # per-language modules (llvm.nix, lua.nix, python.nix, java.nix, latex.nix) —
  # those are about *running* code, which is a separate concern from editing it.
  #
  # The trade-off this buys: nvim is no longer self-contained. `nix run` on the
  # nixvim package alone gets an editor with no language servers, because
  # nixvim/packages.nix no longer declares them.
  home.packages = with pkgs; [
    # Language servers
    bash-language-server
    clang-tools # clangd + clang-format
    cmake-language-server
    jdt-language-server
    lua-language-server
    marksman
    nixd
    pyright
    texlab

    # Formatters. nixfmt is the same one `nix fmt` runs through treefmt
    # (flake/dev.nix), so save-time and CI cannot disagree.
    google-java-format
    nixfmt
    shfmt
    stylua

    # Linters
    lua54Packages.luacheck
    ruff # linter *and* Python formatter
    shellcheck

    # snacks' delete (explorer, picker) shells out to a trash command and
    # `:checkhealth` reported none of `trash`/`gio`/`kioclient` present — every
    # delete would have been permanent. oil is unaffected: since 2.x it writes
    # the FreeDesktop trash spec itself, which is why ~/.local/share/Trash has
    # been filling up correctly all along. trash-cli provides `trash`, the first
    # name snacks looks for.
    trash-cli

    # Debug adapters. gdb (llvm.nix) speaks DAP natively since 14; codelldb is
    # what nvim-dap and Emacs dape both use for C/C++/Rust. The Python adapter
    # is not here — it must be importable by the interpreter itself, so it
    # rides along with python.nix's python3.withPackages.
    vscode-extensions.vadimcn.vscode-lldb.adapter
  ];
}
