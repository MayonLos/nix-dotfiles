# Greeter

Configures the Noctalia greeter as the login screen, with Mango as the default session. Inputs are `host.appearance` and host display facts (output name and scale); the default wallpaper comes from the public `appearance/resources/wallpaper/package.nix` factory using the host palette. The date is Chinese, and the greetd command sets `LC_TIME=zh_CN.UTF-8` while preserving the upstream session data directories and arguments.

Outputs include the system greeter module, synced palette, fonts/cursor assets, login clock/date, keyboard layout, and per-output scaling. `default.nix` is the public entry; `greeter.nix` privately implements these declarations. The greeter's settings are system-side because it runs before the user's Home Manager session.

Removing the feature withdraws the greeter declarations and assets from the system generation. It does not delete user accounts, saved credentials, or other session data. A replacement login manager must be selected separately before applying such a removal.

Astra §6 uses the original small Primary login button as the documented native fallback; its blue/black colors retain contrast. Exact card geometry and cold-login rendering remain runtime acceptance items.
