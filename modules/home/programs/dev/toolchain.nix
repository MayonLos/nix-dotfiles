{ pkgs, ... }:

let
  toolchains = import ../../../../lib/toolchains.nix { inherit pkgs; };
in

{
  # Single source of truth for the tools nvim starts: language servers,
  # formatters and linters. They stay on the profile PATH so the editor closure
  # does not pin a second copy.
  #
  # Compilers, interpreters and build tools deliberately stay in their own
  # per-language modules (llvm.nix, lua.nix, python.nix, java.nix, latex.nix) —
  # those are about *running* code, which is a separate concern from editing it.
  #
  # The trade-off this buys: nvim is no longer self-contained. `nix run` on the
  # Neovim package alone gets an editor with no language servers; language
  # tools come from the selected Home profile or the project environment.
  home.packages = with pkgs; [
    # Language servers
    bash-language-server
    toolchains.llvm.clang-tools # clangd + clang-format; same llvmPackages as llvm.nix
    cmake-language-server
    dockerfile-language-server # docker-langserver
    jdt-language-server
    lua-language-server
    marksman
    # MathWorks' own server. It is not started directly: pkgs/matlab.nix wraps
    # it as `matlab-ls` so it runs inside the FHS environment, which is the only
    # place the MATLAB it drives for completion and formatting will start.
    #
    # Only nvim consumes it today; it lives here because this file is where
    # servers live, and so a future client does not mean moving the package.
    matlab-language-server
    nixd
    pyright
    texlab
    typescript-language-server # ts_ls; tsserver's store path is baked into its cli.mjs
    vscode-langservers-extracted # vscode-{html,css,json,eslint}-language-server
    yaml-language-server

    # Formatters. nixfmt is the same one `nix fmt` runs through treefmt
    # (flake/dev.nix), so save-time and CI cannot disagree.
    google-java-format
    nixfmt
    shfmt
    stylua

    # Linters
    toolchains.luaPackages.luacheck
    ruff # linter *and* Python formatter
    shellcheck

    # The native Neovim file tree uses the FreeDesktop trash command.
    trash-cli
  ];
}
