# MIME defaults and Thunar

`modules/home/base/xdg.nix` maps directory, PDF, text, video, and web MIME types to Thunar, zathura, VS Code, mpv, and Zen desktop entries. Verify that the target `.desktop` file exists in the current package closure before changing a default. `xdg.mimeApps` can be managed even where Home Manager's desktop-entry generator is disabled.

System-level Thunar integration lives in `modules/system/programs/thunar.nix` (volume management, thumbnails, archives, and related services). Home Manager's `thunar-terminal.nix` and `thunar-actions.nix` configure the terminal helper and custom actions.

Home Manager owns `~/.config/Thunar/uca.xml`, so Thunar's custom-action editor cannot persist edits to that file. Add actions declaratively. Thunar rewrites `accels.scm` on exit, so the action shortcut is patched during activation rather than linked read-only.

Thunar's normal copy operation provides file references. The "Copy as Image" action converts an image to PNG and writes both Wayland (`wl-copy`) and X11 (`xclip`) selections. Preserve both targets when changing it, and distinguish image bytes from a copied file path when debugging paste behavior.
