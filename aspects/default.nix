_: {
  # Explicit registry: resources, helpers and recipes are never scanned as modules.
  imports = [
    ./appearance
    ./default-tools
    ./workspace-task
    ./project-workbench
    ./languages
    ./system
    ./command-line
    ./editing
    ./interactive-session
    ./embedded-workbench
    ./ai-workbench
    ./firefox
    ./communication
    ./documents
    ./file-manager
    ./media
    ./gaming
    ./local-containers
    ./local-virtual-machines
  ];
}
