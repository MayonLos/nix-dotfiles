{ den, ... }: {
  imports = [
    ../../desktop/mango-session
    ../../appearance/appearance
  ];
  den.aspects = {
    vscode = { host, ... }: {
      noctaliaIntegrations = [ "vscode" ];
      homeManager.imports = [ ./vscode.nix ];
      provides.${host.name}.includes = [ den.aspects.editing-runtime-host ];
    };
  };
}
