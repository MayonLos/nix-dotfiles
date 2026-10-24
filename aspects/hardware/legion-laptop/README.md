# Legion laptop hardware

Configures the Lenovo Legion hardware stack: boot/kernel settings, firmware, Intel video, NVIDIA PRIME offload, Bluetooth, power, memory, and hardware-specific GPU policy. Inputs are host facts from `host.facts`, including system, Intel/NVIDIA bus IDs, GameMode GPU index, and mpv hardware decoder. The feature does not embed a host's measured values.

The paired `legion-laptop-user` aspect reads host GPU facts to configure mpv decoding and install Lenovo Legion controls. It grants only its selected account the `legion-conservation` group and installs the public CLI `legion-conservation status|toggle`. `status` prints `养护` only when enabled; `toggle` writes 0/1 to the single ideapad attribute, rejecting missing, ambiguous or invalid devices. The host aspect declares that group and a platform/ideapad_acpi udev rule which gives it write access to `conservation_mode` on add/bind/change. No runtime sudo, group creation, daemon or boot-time change of the charge policy is used. Permissions and account membership take effect only after applying the configuration and refreshing the login session; they were not changed during implementation.

The host aspect owns kernel/driver/system declarations; hardware facts are supplied by inventory. `contract.nix` defines the host facts schema. `checks.nix` is the public test hook; `default.nix` is the feature entry and other imported Nix modules are private. The CLI's runtime file is the kernel-owned `/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode`, not a managed user config. A desktop consumer may call the CLI but does not own the hardware permission policy.

Removing the feature withdraws driver, boot, and hardware policy declarations on the next system generation. It does not delete user files, firmware, laptop state, or NVIDIA/Steam profiles; removing drivers while the machine is running requires a later deliberate system switch and reboot.

Removing the user aspect withdraws its group grant and CLI. Removing the host rule does not reset the current firmware charge setting or retroactively revoke a sysfs mode until device recreation/reboot; no removal hook writes charge state.
