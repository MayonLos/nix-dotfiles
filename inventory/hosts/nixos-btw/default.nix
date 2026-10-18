{
  inputs,
  withSystem,
  den,
  ...
}:
let
  inherit (import ../../../lib) importDir;
  facts = import ./facts.nix;
in
{
  imports = [
    ./accounts.nix
    ../../../aspects/system
    ../../../aspects/command-line
    ../../../aspects/default-tools
    ../../../aspects/appearance
    ../../../aspects/languages
    ../../../aspects/editing
    ../../../aspects/interactive-session
    ../../users/mayon.nix
  ];
  den.hosts.${facts.system}.nixos-btw = {
    appearance = import ../../../aspects/appearance/onedark-darker.nix;
    users.mayon = {
      appearance = import ../../../aspects/appearance/onedark-darker.nix;
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
    # Den owns output generation. Preserve the existing package instances and
    # explicit special arguments at the OS instantiation boundary.
    instantiate =
      args:
      withSystem facts.system (
        { pkgs, pkgs-unstable, ... }:
        inputs.nixpkgs.lib.nixosSystem (
          args
          // {
            inherit pkgs;
            specialArgs = (args.specialArgs or { }) // {
              inherit inputs pkgs-unstable;
              hostFacts = facts;
            };
          }
        )
      );
  };
  den.aspects.nixos-btw = {
    includes = with den.aspects; [
      system-maintenance
      legion-laptop
      laptop-network
      closed-ssh-socket
      login-screen
    ];
    nixos = {
      networking.hostName = "nixos-btw";
      system.stateVersion = "25.11";
      nix.settings.trusted-users = [ "mayon" ];
      imports = [
        ./discovered.nix
        ./credentials.nix
        ../../../modules/system/desktop/gamemode.nix
        ../../../modules/system/hardware/debug-probes.nix
        ../../../modules/system/programs/gamescope.nix
        ../../../modules/system/programs/libreoffice.nix
        ../../../modules/system/programs/nh.nix
        ../../../modules/system/programs/steam.nix
        ../../../modules/system/programs/thunar.nix
        ../../../modules/system/services/docker.nix
        ../../../modules/system/virtualisation/libvirt.nix
        inputs.sops-nix.nixosModules.sops
      ];
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        extraSpecialArgs = {
          inherit inputs;
          hostFacts = facts;
        }
        // withSystem facts.system ({ pkgs-unstable, ... }: { inherit pkgs-unstable; });
      };
    };
  };
  den.aspects."mayon@nixos-btw" = {
    includes = with den.aspects; [
      command-line
      terminal
      interactive-session
      default-tools
      neovim
      vscode
      jetbrains
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
    homeManager.imports = importDir ../../../modules/home;
  };
}
