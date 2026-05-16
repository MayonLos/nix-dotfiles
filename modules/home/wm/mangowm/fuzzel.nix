{ pkgs, ... }:
{
  home.packages = [ pkgs.fuzzel ];

  # Fuzzel app launcher — only used in MangoWM session.
  # Niri uses noctalia-shell launcher instead.
  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    [main]
    font=JetBrainsMono Nerd Font:size=12
    icon-theme=Papirus-Dark
    terminal=foot -e
    width=40
    lines=12
    prompt=>_

    [colors]
    background=1f2329ff
    text=abb2bfff
    match=61afefff
    selection=61afef33
    selection-text=dcd7baff
    selection-match=61afefff
    border=3b4252ff

    [border]
    radius=8
    width=1
  '';
}
