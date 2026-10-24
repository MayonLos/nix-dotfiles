_: {
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
          tmuxpConfig =
            id: project:
            pkgs.writeText "tmuxp-${id}.json" (
              builtins.toJSON {
                session_name = "workspace-${id}";
                start_directory = project.directory;
                windows = [
                  {
                    window_name = "workspace";
                    layout = "tiled";
                    panes = [
                      { shell_command = "workspace-editor ."; }
                      { }
                      { }
                    ];
                  }
                ];
              }
            );
          launcherProjects = lib.mapAttrs (
            id: project:
            project
            // lib.optionalAttrs project.workspace {
              tmuxp_config = "${tmuxpConfig id project}";
            }
          ) projects;
          projectJson = pkgs.writeText "workspace-projects.json" (builtins.toJSON launcherProjects);
          hasWorkspaces = builtins.any (project: project.workspace) (builtins.attrValues projects);
          tmuxpPath = if hasWorkspaces then "${pkgs.tmuxp}/bin/tmuxp" else "tmuxp";
          launcher = pkgs.writeShellScriptBin "workspace-project" ''
            exec ${pkgs.python3}/bin/python3 ${./runner.py} \
              --projects-json ${projectJson} \
              --kitty ${pkgs.kitty}/bin/kitty \
              --tmuxp ${tmuxpPath} \
              "$@"
          '';
          desktopEntries = lib.mapAttrs' (
            id: project:
            lib.nameValuePair "workspace-project-${id}" {
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
              actions = {
                editor = {
                  name = "编辑项目";
                  exec = "${launcher}/bin/workspace-project ${id} editor";
                  icon = "accessories-text-editor";
                };
                files = {
                  name = "打开目录";
                  exec = "${launcher}/bin/workspace-project ${id} files";
                  icon = "folder-open";
                };
              }
              // lib.optionalAttrs project.workspace {
                workspace = {
                  name = "工作区";
                  exec = "${launcher}/bin/workspace-project ${id} workspace";
                  icon = "utilities-terminal";
                };
              };
            }
          ) projects;
        in
        {
          home.packages = [
            launcher
            pkgs.kitty
          ]
          ++ lib.optionals hasWorkspaces [
            pkgs.tmux
            pkgs.tmuxp
          ];
          xdg.desktopEntries = desktopEntries;
        };
    };
}
