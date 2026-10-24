{
  pkgs,
  ...
}:

{
  # texlab lives in the selected language aspect. Keep the full environment for the user's
  # complete LaTeX documents; Neovim formula previews are not the reason to
  # retain it. Automatic editor formula rendering has been removed.
  home.packages = with pkgs; [
    texliveFull

    # ImageMagick's PDF delegate and ordinary document conversion still need
    # Ghostscript independently of the removed formula preview helper.
    ghostscript
  ];
}
