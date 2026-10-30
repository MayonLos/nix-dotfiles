# JetBrains IDEs

Installs IntelliJ IDEA, PyCharm, and CLion for the selected user and routes shared native runtime support through `editing-runtime-host`. It has no entity data input; the runtime aspect provides `nix-ld` libraries on the host.

The feature wraps each IDE to supply GLib’s `gsettings` on PATH and its desktop schemas on XDG_DATA_DIRS (the bundled JBR queries them while initializing the desktop theme). It exposes the libraries needed by the bundled Skiko renderer and disables only the overflow hint that was observed to cause a focus loop. The managed IDE packages and wrapper are owned by `default.nix` and `jetbrains.nix`; all Nix files are private.

Removing the feature removes IDE package declarations and its runtime-support selection. Existing IDE settings, plugins, licenses, projects, and caches remain in user data directories.
