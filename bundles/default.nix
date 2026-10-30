{ den, ... }: {
  den.aspects = {
    personal-desktop.includes = with den.aspects; [
      interactive-session
      terminal
      keys-mayon
      default-tools
      firefox
      communication
      documents
      file-manager
      media
    ];
    engineering-workbench.includes = with den.aspects; [
      command-line
      herdr
      neovim
      vscode
      jetbrains
      ai-workbench
      cpp-support
      docker-support
      nix-support
      lua-support
      python-support
      java-support
      shell-support
      latex-support
      markdown-support
      matlab-support
      cmake-support
      web-support
      yaml-support
    ];
    # A human remote workspace; no login service, local daemon or device grants.
    remote-workspace.includes = with den.aspects; [
      command-line
      neovim
      nix-support
    ];
  };
}
