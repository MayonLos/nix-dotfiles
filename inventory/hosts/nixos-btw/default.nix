{
  inputs,
  withSystem,
  den,
  ...
}:
let
  facts = import ./facts.nix;
in
{
  imports = [
    ./accounts.nix
    ../../users/mayon.nix
  ];
  den.hosts.${facts.system}.nixos-btw = {
    appearance = import ../../../aspects/appearance/onedark-darker.nix;
    users.mayon = {
      appearance = import ../../../aspects/appearance/onedark-darker.nix;
      workspaceProjects = {
        dotfiles = {
          directory = "/home/mayon/nix-dotfiles";
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
        inputs.sops-nix.nixosModules.sops
      ];
      programs.gamemode.settings.gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = facts.gpu.gameModeDevice;
        nv_powermizer_mode = 1;
      };
      programs.nh.flake = "/home/mayon/nix-dotfiles";
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
    homeManager = { pkgs, ... }: {
      programs.mpv.config.hwdec = "nvdec-copy";
      home.packages = [ pkgs.lenovo-legion ];
    };
    includes = with den.aspects; [
      personal-desktop
      xorg-session
      engineering-workbench
      project-workbench
      embedded-workbench
      gaming
      local-containers
      local-virtual-machines
    ];
  };
}
