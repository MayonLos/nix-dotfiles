{
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "Mango";
      appearance.password_style = "random";
      keyboard.layout = "us";
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
        path = "/run/current-system/sw/share/icons";
      };
    };
  };

  environment.pathsToLink = [ "/share/wayland-sessions" ];

  environment.systemPackages = [ pkgs.bibata-cursors ];

}
