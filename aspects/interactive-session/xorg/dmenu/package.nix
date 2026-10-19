{ pkgs }:

pkgs.dmenu.override {
  patches = [ ./presentation.patch ];
}
