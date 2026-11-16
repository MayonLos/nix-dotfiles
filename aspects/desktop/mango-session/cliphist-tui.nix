# Private recipe for SHORiN-KiWATA/cliphist-tui. One consumer: the Mango
# clipboard launcher. The pinned commit is the 2026-10-23 tip, which includes
# the non-UTF-8 history-list fix. Upstream has no flake and is not in nixpkgs.
{ pkgs }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "cliphist-tui";
  version = "0.1.0-unstable-2026-10-23";

  src = pkgs.fetchFromGitHub {
    owner = "SHORiN-KiWATA";
    repo = "cliphist-tui";
    rev = "c54f131bb680b433022df0f5e363793646640d7e";
    hash = "sha256-GtRI74NdZNmIOh8xlgWdMTmW7wCpLpMNDQ1NClr99NY=";
  };

  cargoHash = "sha256-E+KKs1F6AiCoLxI6/v20FasNu3qNfDQYNU2BzraJIhI=";

  patches = [ ./resources/cliphist-tui-keep-history.patch ];

  # The crate has no offline test target. Preview and copy shell out to
  # cliphist, fzf and a terminal.
  doCheck = false;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  # fzf invokes this binary's own subcommands, which then look up tools by
  # name. Session PATH still supplies the optional preview commands
  # (ffmpeg, bat, eza, jq, mpv) when they are installed.
  postInstall = ''
    wrapProgram $out/bin/cliphist-tui \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.chafa
          pkgs.cliphist
          pkgs.curl
          pkgs.file
          pkgs.fzf
          pkgs.kitty
          pkgs.libnotify
          pkgs.wl-clipboard
        ]
      }
  '';

  meta = {
    description = "fzf clipboard history with a Kitty image preview on top of cliphist";
    mainProgram = "cliphist-tui";
    license = pkgs.lib.licenses.mit;
  };
}
