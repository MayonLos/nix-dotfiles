{ den, ... }: {
  imports = [
    ../../appearance/appearance
    ../../workspace/workspace-task
  ];
  den.aspects = {
    interactive-session = { host, user, ... }: {
      includes = [ den.aspects.graphical-session-support ];
      # swayosd's udev rules hand the backlight node to video. Volume does not
      # need the group. Membership applies on the next login.
      user.extraGroups = [ "video" ];
      homeManager =
        {
          pkgs,
          ...
        }:
        {
          imports = [
            (import ./mango.nix { palette = user.appearance; })
            (import ./shell.nix { palette = user.appearance; })
            (import ./wallpaper.nix { palette = user.appearance; })
            (import ./lock.nix { palette = user.appearance; })
            ./clipboard.nix
            ./screenshot.nix
          ];
          xdg.dataFile."applications/nvim.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Neovim
            Comment=Terminal text editor
            Exec=kitty --class=Neovim nvim
            Icon=utilities-terminal
            Terminal=false
            Categories=Development;TextEditor;
            StartupWMClass=Neovim
          '';
          nixDotfiles.graphicalSessionTargets = [ "mango-session.target" ];
          home.sessionVariables.NIXOS_OZONE_WL = "1";
          systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";
          # Keep the native notification client available for scripts and for
          # reviewing what the mako daemon draws.
          home.packages = with pkgs; [
            libnotify
            wl-clipboard
            grim
            slurp
            libdecor
          ];
        };
      provides.${host.name}.includes = [ den.aspects.interactive-session-host ];
    };
    interactive-session-host.nixos.imports = [
      ./host/mango.nix
      ./host/portal.nix
    ];
  };
}
