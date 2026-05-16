{ pkgs, ... }:
{
  home.packages = with pkgs; [
    mako
    libnotify
  ];

  # Mako notification daemon config — only used in MangoWM session.
  # Mako is started from MangoWM's autostart_sh, not as a systemd service,
  # so it does not conflict with noctalia notifications in the niri session.
  xdg.configFile."mako/config".text = ''
    font=JetBrainsMono Nerd Font 11
    background-color=#1f2329ee
    text-color=#abb2bf
    border-color=#3b4252
    progress-color=over #61afef44
    border-radius=8
    border-size=1
    padding=10,14
    margin=6
    width=360
    height=120
    max-visible=5
    sort=-time
    layer=overlay
    anchor=top-right
    default-timeout=5000

    [urgency=high]
    border-color=#e06c75
    default-timeout=0
  '';
}
