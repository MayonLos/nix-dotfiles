{
  pkgs,
  ...
}:

{
  # texlab lives in toolchain.nix. texliveFull stays here: Emacs (AUCTeX +
  # pdf-tools) and the CLI both compile documents with it, and it is the one
  # genuinely large thing in this config at ~5.9 GiB.
  home.packages = with pkgs; [
    texliveFull

    # The last link in nvim's maths pipeline, and the one that is invisible
    # when it is missing. snacks.image renders a formula by compiling a LaTeX
    # `standalone` document with pdflatex and then rasterising the PDF with
    # ImageMagick (`magick -density 192 file.pdf[0] -trim`). ImageMagick cannot
    # read PDF itself -- it shells out to Ghostscript through its pdf delegate.
    #
    # Without `gs` the failure is silent in the editor: the .tex, .log and .pdf
    # all appear in ~/.cache/nvim/snacks/image and no image ever shows.
    # Measured: running the delegate by hand gave
    # `sh: line 1: gs: command not found` followed by
    # `magick: FailedToExecuteCommand ... ExecuteGhostscriptCommand`.
    ghostscript
  ];
}
