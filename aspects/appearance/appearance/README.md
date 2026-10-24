# Appearance data

This aspect defines the typed `appearance` input for host and user entities and publishes the current One Dark palette, ANSI colors, and wallpaper assets. Selecting the data aspect alone installs no applications and starts no desktop session.

Inputs are ordinary palette assignments on `host.appearance` and `user.appearance`. The schema validates color fields, fonts, cursor settings, icon theme values, and the optional `reducedMotion` preference. Renderers consume only the values they need in their own feature.

Outputs are the shared data exports below. `noctaliaIntegrations` belongs to `desktop/mango-session` and is validated by its contract. Palette data does not cross host/user scopes automatically.

Public exports: `onedark.nix`, `ansi.nix`, and `resources/wallpaper/` are public data/assets. The public package factory `resources/wallpaper/package.nix` accepts `{ pkgs, palette }` and returns `default`, `generated`, `wallpapers` (named paths) and `directory` (a store link farm). It renders four deterministic 2560×1600 Astra SVG compositions at build time and fetches fixed-hash Unsplash photos; sources and licenses are in `resources/wallpaper/CREDITS.md`. `default.nix` and `contract.nix` are public entry points; other Nix files are private. `ONEDARK-LICENSE` records the palette source license.

Owned files are `contract.nix`, `default.nix`, the public data files, wallpaper factory/resources, and the license. Removing the aspect removes its schema declarations; it does not rewrite application settings or remove wallpaper/user data already copied elsewhere. Rendered configurations disappear only when their consuming features are also removed and a new generation is activated.

The factory does not create home directories. The Mango consumer owns only the managed wallpaper link and missing-directory creation; user `Pictures/Wallpapers/local/` contents remain user-owned and survive feature removal.
