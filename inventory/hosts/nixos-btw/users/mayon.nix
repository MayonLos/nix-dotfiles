{ den, ... }:
let
  flakePath = "/home/mayon/nix-dotfiles";
in
{
  den = {
    hosts.x86_64-linux.nixos-btw = {
      inherit flakePath;
      users.mayon = {
        inherit flakePath;
        avatar = {
          name = "mayon";
          initial = "M";
        };
        secretExports = [
          {
            name = "deepseek-api-key";
            variable = "DEEPSEEK_API_KEY";
          }
        ];
        appearance = import ../../../../aspects/appearance/appearance/onedark.nix;
        workspaceProjects = {
          dotfiles = {
            directory = flakePath;
            label = "Nix 配置工作台";
            workspace = true;
          };
        };
        defaultTools = {
          terminal.argv = [ "kitty" ];
          editor.argv = [ "nvim" ];
          browser = {
            argv = [ "firefox" ];
            desktopId = "firefox.desktop";
          };
          fileManager = {
            argv = [ "thunar" ];
            desktopId = "thunar.desktop";
          };
          guiTextEditor = "code.desktop";
        };
      };
    };
    aspects = {
      nixos-btw.nixos.nix.settings.trusted-users = [ "mayon" ];
      "mayon@nixos-btw" = { user, ... }: {
        user = {
          isNormalUser = true;
          home = "/home/mayon";
          extraGroups = [ "wheel" ];
        };
        homeManager.home = {
          username = "mayon";
          homeDirectory = "/home/mayon";
          stateVersion = "25.11";
        };
        includes = with den.aspects; [
          avatar
          tree-account-tool
          network-manager-user
          clash-tui
          port-tools
          legion-laptop-user
          personal-desktop
          xorg-session
          engineering-workbench
          project-workbench
          embedded-workbench
          gaming
          local-containers
          local-virtual-machines
          voice-input
        ];
      };
    };
  };
}
