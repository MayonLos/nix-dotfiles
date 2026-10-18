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
    ../../users/mayon.nix
  ];
  den.hosts.${facts.system}.nixos-btw = {
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
    ];
    nixos = {
      networking.hostName = "nixos-btw";
      system.stateVersion = "25.11";
      nix.settings.trusted-users = [ "mayon" ];
      imports = [
        ./discovered.nix
        ./credentials.nix
        ../../../modules/system/desktop/gamemode.nix
        ../../../modules/system/desktop/greetd.nix
        ../../../modules/system/desktop/mango.nix
        ../../../modules/system/desktop/xdg.nix
        ../../../modules/system/hardware/audio.nix
        ../../../modules/system/hardware/debug-probes.nix
        ../../../modules/system/programs/gamescope.nix
        ../../../modules/system/programs/libreoffice.nix
        ../../../modules/system/programs/nh.nix
        ../../../modules/system/programs/nix-ld.nix
        ../../../modules/system/programs/steam.nix
        ../../../modules/system/programs/thunar.nix
        ../../../modules/system/security/polkit.nix
        ../../../modules/system/services/docker.nix
        ../../../modules/system/user/fonts.nix
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
      default-tools
    ];
    homeManager.imports = importDir ../../../modules/home;
    # This binding selects the Noctalia template consumer; remote CLI keeps Default.
    homeManager.programs.btop.settings.color_theme = "noctalia";
  };
}
