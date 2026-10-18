{ lib, ... }: {
  den.aspects."mayon@nixos-btw" = {
    user = { pkgs, ... }: {
      isNormalUser = true;
      home = "/home/mayon";
      extraGroups = [
        "wheel"
        "networkmanager"
        "gamemode"
        "input"
        "dialout"
      ];
      packages = [ pkgs.tree ];
    };
    homeManager = {
      programs.zsh.initContent = lib.mkBefore ''
        for _s in deepseek-api-key:DEEPSEEK_API_KEY; do
          _file="/run/secrets/''${_s%%:*}"
          _var="''${_s##*:}"
          [ -r "$_file" ] && export "$_var=$(<"$_file")"
        done
        unset _s _file _var

      '';
      home = {
        username = "mayon";
        homeDirectory = "/home/mayon";
        stateVersion = "25.11";
      };
    };
  };
}
