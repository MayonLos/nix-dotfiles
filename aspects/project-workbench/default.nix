{ den, ... }:
{
  den.schema.user.imports = [ ./contract.nix ];

  den.aspects.project-workbench =
    { user, ... }:
    let
      projects = user.workspaceProjects;
      safeId = id: builtins.match "[a-z0-9][a-z0-9-]*" id != null;
    in
    assert builtins.all safeId (builtins.attrNames projects);
    {
      homeManager =
        { pkgs, lib, ... }:
        let
          projectJson = pkgs.writeText "workspace-projects.json" (builtins.toJSON projects);
          launcher = pkgs.writeShellScriptBin "workspace-project" ''
            exec ${pkgs.python3}/bin/python3 ${./runner.py} \
              --projects-json ${projectJson} \
              --kitty ${pkgs.kitty}/bin/kitty \
              "$@"
          '';
          desktopEntries = lib.mapAttrs' (id: project: {
            name = "workspace-project-${id}";
            value = {
              name = project.label;
              genericName = "Project workspace";
              comment = "Open project workspace in Kitty";
              exec = "${launcher}/bin/workspace-project ${id} terminal";
              icon = "folder-development";
              terminal = false;
              type = "Application";
              categories = [
                "Development"
                "Utility"
              ];
            };
          }) projects;
        in
        {
          home.packages = [
            launcher
            pkgs.kitty
          ];
          xdg.desktopEntries = desktopEntries;
        };
    };
}
