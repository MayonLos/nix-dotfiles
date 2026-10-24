# Mango session

Provides the Mango Wayland desktop and its Noctalia shell integration. Inputs are `user.appearance`, host display facts, selected `noctaliaIntegrations`, and the public `nixDotfiles.graphicalSessionTargets` option from session support.

Outputs include Mango/Noctalia configuration, clipboard bridges, screenshot and OCR tools, per-session environment, and host-side Mango/portal modules routed through `interactive-session-host`. The `noctaliaIntegrations` quirk is declared here and validated by `contract.nix` before it is consumed to render selected application integrations. The feature owns its session target and Noctalia service lifecycle; it does not select the login greeter.

`default.nix` and `contract.nix` are public. `mango.nix`, `noctalia.nix`, `clipboard.nix`, `screenshot.nix`, `tesseract-ocr.nix`, and `host/` are private implementation. `checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (as needed). Other Nix files are private.

Removing the feature withdraws Mango and Noctalia configuration, session services, and screenshot/clipboard declarations when a new generation is activated. It leaves user documents, Noctalia history/settings outside declared paths, saved sessions, and other application state untouched; it does not stop or switch the running session by itself.
