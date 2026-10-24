{
  inputs,
  den,
  ...
}:
let
  facts = import ./facts.nix;
in
{
  imports = [
    ./users/mayon.nix
    ../../users/mayon.nix
  ];
  den.hosts.${facts.system}.nixos-btw = {
    avatar = {
      name = "mayon";
      initial = "M";
    };
    appearance = import ../../../aspects/appearance/appearance/onedark-darker.nix;
    inherit facts;
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
      imports = [
        ./hardware-configuration.nix
        ./secrets.nix
        inputs.sops-nix.nixosModules.sops
      ];

    };
  };

}
