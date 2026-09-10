---
name: host-hardware
description: Host-level decisions on nixos-btw (Intel + NVIDIA laptop) — GPU offload, containers and VMs, OOM protection, sshd exposure, networking/proxy, and the removal of Flatpak. Use when touching NVIDIA or PRIME settings, when the machine oopses or hangs at shutdown, when working with Docker or libvirt, when changing firewall or sshd, when a proxy/TUN interface breaks networking, or when tempted to add Flatpak or reach for a Flatpak package.
---

# Host: nixos-btw

Single host: Intel + NVIDIA laptop, 2560×1600 internal display, niri compositor.
Entry point `hosts/nixos-btw/default.nix`, hardware in `hosts/nixos-btw/hardware.nix`.

## NVIDIA — PRIME offload, finegrained off

`modules/system/hardware/nvidia.nix` uses PRIME **offload**, not a full-time
discrete GPU.

Two settings there are about the same shutdown crash and must stay as they are:

- `powerManagement.finegrained = false` — RTD3 teardown oopses
  `nvidia_modeset` at shutdown on this laptop. Turning it back on to "save
  power" reintroduces a kernel oops on every poweroff.
- `nvidiaPersistenced = true` — makes shutdown take the proper driver teardown
  path, avoiding the `nv_drm_master_drop` → `ReleaseOwnership` NULL deref.

`open = true` (the open kernel modules) and a niri-specific application profile
capping `GLVidHeapReuseRatio` (a VRAM leak workaround) are also set in that file.
CUDA lives in `modules/system/hardware/cuda.nix` and the `nix develop .#cuda`
shell.

## Containers and VMs

- **Rootless Docker** — `modules/system/services/docker.nix`. `DOCKER_HOST` is
  set via `setSocketVariable`. A weekly `docker system prune` user timer runs.
  Anything assuming a root daemon socket at `/var/run/docker.sock` will fail.
- **KVM/libvirt** — `modules/system/virtualisation/libvirt.nix`, with
  `virt-manager` and swtpm. `mayon` is in the `libvirtd` and `kvm` groups.

## earlyoom

`modules/system/services/oom.nix` runs earlyoom as a system service to prevent
whole-desktop OOM freezes. Keep it enabled.

## sshd is enabled but closed

`modules/system/services/openssh.nix`: the service runs, `openFirewall = false`,
password auth is off, and **no key has ever been authorised**.

Making SSH usable means doing both at once — re-open the port *and* add
`users.users.mayon.openssh.authorizedKeys.keys`. Opening the port alone gets you
an exposed daemon nobody can log into; adding a key alone changes nothing.

## Networking / proxy

Clash Verge's TUN device is trusted in
`networking.firewall.trustedInterfaces` (`modules/system/core/network.nix`).
Both **`Meta`** (verge-mihomo 1.19.x) and **`Mihomo`** (older versions) are
listed on purpose — when the name does not match, TCP inside the TUN is dropped
by the INPUT chain while UDP/DNS keeps working, which presents as "the proxy is
on and now nothing connects". Do not prune either name.

### nix-daemon has its own proxy

`modules/system/core/nix.nix` sets `http_proxy`/`https_proxy` to
`socks5h://localhost:7897` (Clash Verge's mixed port) **on the nix-daemon unit**.
Substituter and tarball downloads run inside that daemon, which inherits nothing
from your shell; flake *input* fetches happen in the `nix` client process and use
the user environment instead, which is why the two can behave differently.

This hard-depends on Clash listening there: with Clash down, daemon-side
downloads fail outright rather than falling back to a direct connection. That is
the accepted trade for them not timing out one at a time when it is up.
`no_proxy` excludes loopback because `socks5h` would otherwise hand even local
name resolution to the proxy.

## No Flatpak — do not add it back

It was removed after measuring: 6.1 GiB on disk for four apps whose bodies
totalled 578 MB. `go-musicfox` alone pinned the whole freedesktop 24.08 runtime
stack (~1.65 GiB), plus an orphaned GNOME Platform 49 (1.1 GB) that
`flatpak uninstall --unused` refused to collect.

All four moved to nixpkgs:

- QQ and WeChat → `modules/home/programs/apps/im.nix`
- Typora and go-musicfox → `modules/home/packages.nix`

Chinese input still works because `qq` opts into wayland text-input-v3, and
`wechat-uos` maps `XMODIFIERS` onto `QT_IM_MODULE`/`GTK_IM_MODULE`. QQ also
needs a `LD_LIBRARY_PATH` wrapper for Wayland screen sharing — its bundled
Chromium fails to `dlopen` libpipewire otherwise.

Reach for nixpkgs, `nix-ld` (`modules/system/programs/nix-ld.nix`) or an FHS
wrapper before considering Flatpak again.

## Everything else on this host

Small, comment-free modules nobody has needed a rule for yet — read the file, it
is short: `core/boot.nix`, `core/locale.nix`, `hardware/audio.nix` (pipewire),
`hardware/bluetooth.nix`, `hardware/firmware.nix`, `hardware/intel-video.nix`,
`security/polkit.nix`, `services/systemd.nix`, `user/mayon.nix`,
`user/environment.nix`.

Neighbouring skills own the rest: `gaming-stack` for Steam/gamescope/gamemode,
`desktop-niri` for the compositor and greeter, `desktop-apps` for theming and
fonts, `shell-terminal` for zsh and the terminal stack, `nix-modules` for the
flake and channel rules.

