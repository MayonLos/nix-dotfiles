{
  pkgs,
  ...
}:

{
  users.users.mayon = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"
      "input"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      tree
    ];
  };
}
