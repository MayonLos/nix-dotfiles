# Portals, capture, greeter, and screenshots

Start from the current declarations in `modules/system/desktop/xdg.nix` and the Mango NixOS module. The repository currently routes FileChooser to `gtk`, Settings to `gnome`, OpenURI to `gtk`, and uses `gnome` as the common default. ScreenCast and Screenshot use `wlr` via Mango's backend configuration. Confirm evaluated routing before changing backend assignments.

Add portal packages through `xdg.portal.extraPortals`; do not replace the merged list with `mkForce`. The active set includes Mango's wlr/gtk backends and the explicitly added GNOME portal. Preserve GNOME keyring because the Secret portal route depends on its service. Portal implementations are interface-specific: choose the file chooser independently from ScreenCast/Screenshot, and retain the wlroots capture backend for Mango.

FileChooser uses GTK because the pinned GNOME backend delegates to Nautilus,
which this host does not register as an activatable service. Switching it to
GNOME without handling that dependency previously broke file dialogs.
Do not remove GNOME merely because FileChooser is GTK: Settings still uses it.

`xdg.portal.wlr.settings.screencast` currently names `eDP-1` and sets `chooser_type = "none"`, matching the one-output host. Revisit the chooser when display topology changes. NixOS generates the service config; inspect the running service's arguments before assuming a user config file is read.

`modules/system/desktop/greetd.nix` links Wayland session desktop files into the system profile so the greeter can enumerate Mango; preserve that link and confirm Mango appears in the greeter after changes. `modules/home/programs/apps/screenshot.nix` adds the Mango detector and repoints mark-shot's mutable config. For selection problems inspect `mmsg get all-clients` and detector output before adding scale arithmetic.

The detector uses global logical client rectangles and filters visibility;
its wrapper is a symlinkJoin to avoid rebuilding the Qt app for script edits.
Activation changes only `windowDetection.command` in mark-shot's mutable JSON.
Preserve all other user keys. Mango's system module disables unused speechd;
check inherited desktop services before treating that override as redundant.
