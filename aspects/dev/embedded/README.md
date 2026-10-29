# STM32 / Cortex-M workbench

`embedded-workbench` configures firmware tools for the selected user and routes udev support to the host once, even when multiple accounts select the feature. Inputs are the host platform and selected host facts; user authorization is `dialout`. It does not own project SDK versions or project files.

Outputs include ARM GCC/GDB, OpenOCD, ST-Link, probe-rs, DFU/UART tools, CubeMX, `tio`, CMake, Ninja, pkg-config, and host GDB. The ARM compiler has lower profile priority so host GDB wins conflicting data paths; the binaries use their own store data directories. OpenOCD/ST-Link rules provide active-seat `uaccess`; the empty `plugdev` group only satisfies upstream rule references and grants no membership-based access. This does not guarantee access to every probe-rs device or remote sessions without an active seat.

`default.nix`, `home.nix`, `host.nix`, and `rules.nix` implement the feature. `checks.nix` is a public test hook with the repository feature-check signature `{ pkgs, lib, system, nixos, home, appearance }` (only required arguments are consumed). `contract.nix` publicly exports `seatRules` as a function of `{ pkgs }`; other Nix files are private. STM32CubeProgrammer was removed on 2026-10-29 because its login-gated installer cannot be fetched automatically; flash through OpenOCD, st-flash, probe-rs or dfu-util instead.

The locked ST-Link rules used `MODE:="0666"`, without `uaccess`; their final assignment could not be overridden by later OpenOCD rules. `rules.nix` converts them to `MODE:="0660", TAG+="uaccess"` while preserving device aliases, and fails if the expected upstream rules change. The tool binaries themselves are not patched. Project flakes remain responsible for project-specific toolchain versions and build files.

Checks cover user/host selection, provider deduplication, rule permissions, tools, and removal behavior. They do not prove a real board's ACL, GUI startup, or flashing. Removing this feature withdraws its packages, rules, and group declaration; it preserves project trees, firmware, CubeMX projects, application preferences, and device state. No system activation or hardware test is implied.

Public reference: [probe-rs Linux setup](https://probe.rs/docs/getting-started/probe-setup/).
