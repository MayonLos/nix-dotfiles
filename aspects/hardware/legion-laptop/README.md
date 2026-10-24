# Legion laptop hardware

Configures the Lenovo Legion hardware stack: boot/kernel settings, firmware, Intel video, NVIDIA PRIME offload, Bluetooth, power, memory, and hardware-specific GPU policy. Inputs are host facts from `host.facts`, including system, Intel/NVIDIA bus IDs, GameMode GPU index, and mpv hardware decoder. The feature does not embed a host's measured values.

The paired `legion-laptop-user` aspect reads host GPU facts to configure mpv decoding and install Lenovo Legion controls. The host aspect owns kernel/driver/system declarations; hardware facts are supplied by inventory. `contract.nix` defines the host facts schema. `default.nix` and the imported Nix modules are private.

Removing the feature withdraws driver, boot, and hardware policy declarations on the next system generation. It does not delete user files, firmware, laptop state, or NVIDIA/Steam profiles; removing drivers while the machine is running requires a later deliberate system switch and reboot.
