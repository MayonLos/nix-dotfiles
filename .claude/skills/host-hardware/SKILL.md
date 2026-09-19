---
name: host-hardware
description: Host-level decisions on nixos-btw (Intel + NVIDIA laptop) — GPU offload, containers and VMs, OOM protection, sshd exposure, networking/proxy, and the removal of Flatpak. Use when touching NVIDIA or PRIME settings, when the machine oopses or hangs at shutdown, when working with Docker or libvirt, when changing firewall or sshd, when a proxy/TUN interface breaks networking, or when tempted to add Flatpak or reach for a Flatpak package.
---

# Host: nixos-btw

Single host: Intel + NVIDIA laptop, 2560×1600 internal display, mango compositor.
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

`open = true` (the open kernel modules) and a compositor-specific application profile
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

### A build that hangs forever is usually a stalled substituter fetch

Measured 2026-09-10: `nix build` of the system toplevel sat for **37 minutes**
with no progress — no compiler processes, no build directories, nothing landing
in the store — while `curl -sI https://cache.nixos.org/nix-cache-info` answered
in 0.22 s. A download connection had wedged inside the TUN and nix waited on it
with no timeout of its own.

The fix is to give nix one:

```sh
nix build … --option stalled-download-timeout 20 --option connect-timeout 10
```

With those, the wedged connection is dropped and retried instead of pinning the
build. Worth reaching for the moment a build looks frozen rather than slow.

**How to tell frozen from slow — and one trap.** Do *not* use
`find /nix/store -maxdepth 1 -newermt '-5 minutes'`: nix normalises store path
mtimes to the epoch, so that always returns nothing and every build looks dead.
Sample the path count instead, and check throughput separately:

```sh
a=$(ls /nix/store | wc -l); sleep 45; b=$(ls /nix/store | wc -l); echo $((b-a))
awk '{s+=$1} END {print s}' /sys/class/net/*/statistics/rx_bytes   # twice, 20s apart
```

Bytes moving with zero new paths is normal — nix registers a path only after the
whole NAR verifies, and a single CUDA or Electron NAR is hundreds of MB. Zero on
both is the real hang.

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

## The kernel is pinned by NVIDIA, not by taste

`modules/system/core/boot.nix` sets `boot.kernelPackages = pkgs.linuxPackages` —
nixpkgs' LTS, **not** `linuxPackages_zen`. Zen currently tracks Linux 7.2, and
NVIDIA's open 595 module does not build against it (`strncpy` was removed from
the kernel API). Moving off LTS is an NVIDIA-support question; check that the
driver builds before touching this line.

Three more load-bearing settings live in the same file:

- `options legion_laptop force=1` — the Lenovo EC module refuses this laptop's
  DMI without it, and `boot.extraModulePackages` carries
  `lenovo-legion-module` for the same reason.
- `options nvidia NVreg_PreserveVideoMemoryAllocations=1` — suspend/resume, see
  the NVIDIA section above.
- `systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp"` — `/tmp` is
  tmpfs here (`boot.tmp.useTmpfs`), and a large nixpkgs build does not fit in
  RAM.

`hardware/intel-video.nix` is likewise not decorative: VAAPI on the Raptor Lake
iGPU needs `intel-media-driver` (iHD) plus `vpl-gpu-rt` in
`hardware.graphics.extraPackages`, or every `vaInitialize` on the Intel render
node fails and browsers and mpv silently decode on the CPU. The render nodes are
inverted from what you would guess: **renderD128 is nvidia, renderD129 is i915**.

## Networking bits that are easy to "tidy" wrongly

`modules/system/programs/clash.nix` enables `programs.clash-verge` with
`serviceMode` and `tunMode`, and sets `services.resolved.settings.Resolve
.DNSStubListener = "no"`. That last line is not cleanup fodder: the TUN stack
wants :53 for itself, and leaving systemd-resolved's stub listener on it is the
classic "everything resolves until the proxy starts" failure. The TUN interface
name and the nix-daemon proxy wiring are covered in the proxy section above.

## Debug probes and serial

`modules/system/hardware/debug-probes.nix` puts `openocd` and `stlink` into
`services.udev.packages`, which installs their upstream rules. Those rules tag
ST-Link, CMSIS-DAP and J-Link devices `uaccess`, so logind hands the logged-in
seat access dynamically -- there is no `plugdev` group here and none is needed.

The serial console is the exception and the reason `mayon` is in `dialout`:
`/dev/ttyUSB*` and `/dev/ttyACM*` come up root:dialout with no uaccess tag, so
`tio /dev/ttyACM0` needs real group membership. The toolchain those devices are
for is in `modules/home/programs/dev/embedded.nix` (`dev-toolchain` skill).

## Everything else on this host

Short modules with no rule of their own — read the file, including its comments:
`core/locale.nix` (zh_CN is built deliberately), `hardware/audio.nix`
(pipewire), `hardware/bluetooth.nix`, `hardware/firmware.nix`,
`security/polkit.nix`, `services/systemd.nix`, `user/mayon.nix`,
`user/environment.nix`, `programs/libreoffice.nix` (libreoffice-qt + en_US
hunspell/hyphen dictionaries).

`programs/nh.nix` enables `nh` with `flake = "/home/mayon/nix-dotfiles"` — an
absolute path, so moving or renaming the repo breaks `nr`/`nc` until it is
updated — and `clean.extraArgs = "--keep 5 --keep-since 14d"`, which is the
retention policy behind the weekly GC.

`programs/zsh.nix` (system) is three lines but one of them matters:
`programs.command-not-found.enable = false`, because the default handler reads a
stale channel database and would override nix-index's hook. See
`shell-terminal`.

Neighbouring skills own the rest: `gaming-stack` for Steam/gamescope/gamemode,
`desktop-mango` for the compositor and greeter, `desktop-apps` for theming and
fonts, `shell-terminal` for zsh and the terminal stack, `nix-modules` for the
flake and channel rules.

