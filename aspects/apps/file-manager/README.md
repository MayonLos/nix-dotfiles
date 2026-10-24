# File manager

Installs Thunar for the selected user and host support for Thunar, GVfs, and thumbnailing. It needs the normal package set; host support is routed through `file-manager-host-support`.

Outputs include the managed Thunar custom actions, terminal launcher integration, archive plugin, volume management, GVfs, and Tumbler. Custom actions copy paths or image data across Wayland and X11 selections, paste clipboard images as new PNG files, and create symlinks from copied file URIs. Existing custom action configuration is represented declaratively by `thunar-actions.nix`.

In a Noctalia session, the shared session-support GTK3 asset template styles Thunar paths, table headers, details-view cells (including filenames), and status values with the palette monospace family; GTK TreeView has no per-cell CSS nodes. Selected rows keep the neutral selection surface and use a narrow blue inset marker. Noctalia remains the single writer of the generated GTK CSS.

Owned files are `default.nix`, `host.nix`, `thunar-actions.nix`, and `thunar-terminal.nix`; all Nix files are private. Removing the feature withdraws its packages, host services, and managed action declarations. Existing files, thumbnails, and user configuration data are retained; an existing HM-managed file may be backed up according to the host backup policy.
