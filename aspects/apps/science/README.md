# Science

Installs and integrates scientific desktop applications. Only GNU Octave is
declared today; later science tools belong in this feature instead of another
one-package feature.

## Input

No schema, quirk or host input. Select the feature through a bundle or with
`includes = [ den.aspects.science ]`. Packages come from the locked stable
`pkgs` instance.

## Output

`pkgs.octaveFull` is installed as the wrapped `octave` command and its
`org.octave.Octave` desktop entry. In the locked nixpkgs, `octaveFull` only adds
the Qt 5 GUI build (`enableQt = true`) on top of `octave`; it does **not** pull
in the `octavePackages` toolboxes. Adding a toolbox later means changing the
package factory to `octaveFull.withPackages (ps: [ ... ])`; each toolbox is
compiled against this exact Octave and is not in the binary cache.

The GUI is a Qt 5 application while the session sets
`QT_QPA_PLATFORMTHEME=qt6ct`. Qt 5 cannot load that plugin and would render the
light Fusion palette. `octave.nix` therefore wraps `octave` with
`QT_QPA_PLATFORMTHEME=qt5ct` and prefixes `QT_PLUGIN_PATH` with the qt5ct plugin
directory, and rewrites the desktop entry to the wrapper so launcher starts get
the same environment. The palette is not owned here: `graphical-session-support`
seeds `~/.config/qt5ct/qt5ct.conf` from the shared One Dark colour file, so the
theme follows the session palette. Without that support selected, Octave still
starts but keeps the default palette.

## Boundaries

Octave is Qt 5, so the session-wide Qt 6 environment is left untouched. The
feature does not install toolboxes, Java/MEX build dependencies, or MATLAB
compatibility shims. Editor support already comes from the Neovim treesitter
registration that maps the `octave` filetype to the MATLAB grammar; this feature
adds no editor configuration.

## Owned files and state

This feature owns `default.nix`, `octave.nix`, this README, and the HM package
link. It writes no activation script, systemd unit or MIME entry.

Octave's own settings, command history and scripts live under the user's
`~/.config/octave` and `~/.local/share/octave` (or the corresponding XDG
overrides); they are user state and are not seeded, migrated or deleted here.
Removing the feature removes the package and desktop entry and leaves that state
on disk.

## Verification

The package was built from the locked nixpkgs (`octave-11.1.0`) and the wrapper
environment was checked statically; GUI rendering, Qt 5 plugin loading and
desktop-launcher behaviour need a graphical session and were not exercised in
the change that added this feature.
