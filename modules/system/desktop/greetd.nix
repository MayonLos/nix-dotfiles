{
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  programs.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "Niri";
      appearance.password_style = "random";
      keyboard.layout = "us";
      cursor = {
        theme = "Bibata-Modern-Ice";
        size = 24;
        path = "/run/current-system/sw/share/icons";
      };
    };
  };

  services.greetd.settings.default_session.user = "greeter";

  environment.pathsToLink = [ "/share/wayland-sessions" ];

  environment.systemPackages = [ pkgs.bibata-cursors ];

  systemd.user.services.niri.enableDefaultPath = false;
}
