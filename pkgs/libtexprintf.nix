# Not in nixpkgs (checked 2026-09: no libtexprintf, no utftex attribute), and
# it is the only thing that renders a TeX fraction as an actual two-level box
# in a terminal. render-markdown.nvim shells out to `utftex` for `$...$` blocks
# — see the comment in modules/home/programs/dev/toolchain.nix.
#
# importDir would evaluate this as a Home Manager module if it lived under
# modules/, which is why package expressions sit at the repo root instead.
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "libtexprintf";
  version = "1.31";

  src = fetchFromGitHub {
    owner = "bartp5";
    repo = "libtexprintf";
    tag = "v${finalAttrs.version}";
    hash = "sha256-OXDcohfSfik0H1MpoznN267OVTYkW75N+TIF6lRRvZ0=";
  };

  # The tarball ships configure.ac but no configure; autogen.sh is just
  # `autoreconf -i`, which is what this hook runs. Only dependency is libm.
  nativeBuildInputs = [ autoreconfHook ];

  meta = {
    description = "Render TeX equations as UTF-8 text, with the utftex CLI";
    homepage = "https://github.com/bartp5/libtexprintf";
    license = lib.licenses.gpl3Plus;
    mainProgram = "utftex";
    platforms = lib.platforms.unix;
  };
})
