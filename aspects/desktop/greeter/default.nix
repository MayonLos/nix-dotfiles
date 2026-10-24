{ den, ... }: {
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    login-screen = { host, ... }: { nixos = import ./greeter.nix { palette = host.appearance; }; };
  };
}
