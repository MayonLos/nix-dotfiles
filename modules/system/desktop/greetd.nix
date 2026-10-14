{
  pkgs,
  inputs,
  ...
}:

let
  desktop = import ../../../lib/desktop.nix;
in
{
  imports = [ inputs.noctalia-greeter.nixosModules.default ];

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "Mango";
      appearance.password_style = "random";
      keyboard.layout = "us";
      # Automatic DPI chose 2.0 on this panel (boot log: 1280x800 logical),
      # making the same 24px cursor larger than Mango's 1.5x session.
      output.scale = desktop.primaryOutputScale;
      cursor = {
        theme = desktop.cursor.name;
        size = desktop.cursor.size;
        path = "/run/current-system/sw/share/icons";
      };
    };
  };

  environment.pathsToLink = [ "/share/wayland-sessions" ];

  environment.systemPackages = [ pkgs.bibata-cursors ];

}
