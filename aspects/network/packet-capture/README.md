# Packet capture

Installs Wireshark for the selected user and enables the NixOS Wireshark
integration for the host. The feature exists because the GUI and the capture
privilege are separate concerns: the package must be available to the desktop
user, while the `dumpcap` wrapper and the `wireshark` group are host state.

## Input

No schema, quirk or package input. The user is added to the `wireshark` group by
the user class. Host content is routed through the `packet-capture-host` aspect
with `provides.${host.name}.includes`, so selecting the feature in a user binding
delivers it to that user's host only.

## Output

The host enables `programs.wireshark` with `package = pkgs.wireshark`:
Wireshark (GUI and CLI tools) is installed in `environment.systemPackages`, a
`wireshark` group is created, and `/run/wrappers/bin/dumpcap` gets
`cap_net_raw,cap_net_admin+eip`. The selected user joins that group, which is what
lets the wrapper capture without root. The module's default package is
`wireshark-cli`; this feature overrides it because the desktop use case needs the
GUI.

`usbmon` stays disabled: USB capture would add udev rules and is a separate
capability that should only be enabled for a concrete USB analysis need. No
service, socket or desktop session target is added.

## Boundaries

The capability is limited to the `wireshark` group and to packet capture;
membership does not grant general root access. Enabling the feature changes the
host generation (system packages, group, wrapper), so it is selected on a desktop
host, not on a server role. Other network tooling (Clash TUN, nftables) remains
owned by its features; Wireshark is read-only observation and does not replace
their configuration.

## Owned files and state

This feature owns `default.nix` and this README. The host declarations are NixOS
module state (package, group, wrapper), not files in the home directory.
Wireshark's own profiles, preferences, capture files and recent-file lists live
under `~/.config/wireshark` and the user's chosen capture paths; they are user
state and are not seeded, migrated or deleted here. Removing the feature removes
the package, group membership and wrapper from the next generation and leaves
captures and profiles on disk.

## Verification

The change was evaluated and the system closure was built; installing the
feature requires the next `nixos-rebuild switch`. Actual packet capture needs a
running graphical session and a real interface, and was not exercised while
adding this feature.
