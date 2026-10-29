_: {
  # Explicit registry: resources, helpers and recipes are never scanned as modules.
  imports = [
    ./appearance/avatar
    ./appearance/appearance
    ./system/default-tools
    ./workspace/workspace-task
    ./workspace/project-workbench
    ./dev/languages
    ./system/maintenance
    ./network/laptop-network
    ./network/clash-tui
    ./network/remote-access
    ./hardware/legion-laptop
    ./cli/shell
    ./cli/terminal
    ./cli/herdr
    ./dev/neovim
    ./dev/vscode
    ./dev/jetbrains
    ./dev/editor-runtime
    ./desktop/session-support
    ./desktop/mango-session
    ./desktop/xorg-session
    ./desktop/greeter
    ./dev/embedded
    ./dev/ai-agents
    ./apps/firefox
    ./apps/communication
    ./apps/documents
    ./apps/file-manager
    ./apps/media
    ./apps/gaming
    ./dev/containers
    ./dev/virtual-machines
  ];
}
