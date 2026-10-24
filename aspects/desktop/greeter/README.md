# Greeter

Configures the Noctalia greeter as the login screen, with Mango as the default session. Inputs are `host.appearance` and host display facts (output name and scale); static wallpaper data comes from the public appearance asset export.

Outputs include the system greeter module, synced palette, fonts/cursor assets, login clock/date, keyboard layout, and per-output scaling. `default.nix` and `greeter.nix` own these declarations; all Nix files in this feature are private. The greeter's settings are system-side because it runs before the user's Home Manager session.

Removing the feature withdraws the greeter declarations and assets from the system generation. It does not delete user accounts, saved credentials, or other session data. A replacement login manager must be selected separately before applying such a removal.
