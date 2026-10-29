{ den, ... }: {
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects = {
    vscode = { host, user, ... }: {
      noctaliaIntegrations = [ "vscode" ];
      homeManager.imports = [ (import ./vscode.nix { palette = user.appearance; }) ];
      provides.${host.name}.includes = [ den.aspects.editing-runtime-host ];
    };
  };
}
