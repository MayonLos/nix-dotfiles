{
  pkgs,
  ...
}:

{
  programs.zathura = {
    enable = true;
    package = pkgs.zathura;
    options = {
      adjust-open = "best-fit";
      selection-clipboard = "clipboard";
    };
  };
}
