# Avatar identity

The public `default.nix` registers the `avatar` and routed `avatar-host` aspects. `contract.nix` defines typed host/user avatar data (`name`, `initial`); each side consumes its own appearance palette. Data alone creates no output.

Selecting `avatar` produces the PNG, the managed user/system avatar paths, and the idempotent `.face` and AccountsService seeds. It does not select or configure the desktop session; no lockscreen widget is declared by this feature.

This feature owns its private `package.nix`, `home.nix`, `nixos.nix`, generated PNG files, and seed scripts. Existing files, symlinks, custom AccountsService Icon values and user data are preserved. Removing the selection removes managed outputs and the integration contribution on activation; existing seeded `.face`/AccountsService state is retained. Mango owns its widget declaration. No graphical session is enabled by avatar alone.
