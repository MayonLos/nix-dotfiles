{ pkgs, ... }:
{
  # Keep the previous sudo policy: password-authenticated wheel, SETENV,
  # and executable access for all users (authorization still uses sudoers).
  security.sudo.enable = false;
  security.sudo-rs = {
    enable = true;
    wheelNeedsPassword = true;
    execWheelOnly = false;
    defaultOptions = [ "SETENV" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    lshw
    gnumake
    unzip
    unrar
  ];
}
