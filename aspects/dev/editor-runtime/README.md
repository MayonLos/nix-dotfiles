# Editor runtime support

Enables NixOS `nix-ld` with the shared native libraries required by downloaded editor and extension binaries. Editor features route to this host aspect when selected. It has no user preference or appearance input.

The output is the system `nix-ld` configuration and compatibility library set. `default.nix` and `host.nix` are owned, private Nix files. Removing the aspect withdraws this compatibility layer from the next system generation; it does not remove editor profiles, extensions, or user projects.
