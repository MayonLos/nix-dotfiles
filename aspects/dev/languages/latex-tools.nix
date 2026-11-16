{
  pkgs,
  ...
}:

{
  # texlab lives in the selected language aspect. Keep the full environment for
  # the user's complete LaTeX documents; the editor's live formula preview also
  # renders through it.
  home.packages = with pkgs; [
    texliveFull

    # ImageMagick's PDF delegate and ordinary document conversion need
    # Ghostscript independently of texlab.
    ghostscript
  ];
}
