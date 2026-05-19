{ pkgs, ... }:
{
  home.packages = [ pkgs.fuzzel ];

  xdg.configFile."fuzzel/fuzzel.ini".text = ''
    [main]
    font=JetBrainsMono Nerd Font:size=13
    icon-theme=Papirus-Dark
    terminal=foot -e
    width=42
    lines=10
    prompt=
    padding=4,4
    inner-padding=10
    image-size-ratio=0.4
    letter-spacing=0

    [colors]
    background=1e222aee
    text=abb2bfff
    match=61afefff
    selection=2c313aff
    selection-text=abb2bfff
    selection-match=61afefff
    border=61afef66

    [border]
    radius=12
    width=1
  '';
}
