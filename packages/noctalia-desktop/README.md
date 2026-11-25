# noctalia-desktop

Experimental package factory for the Noctalia desktop stack (2026-11). It is
consumed from `nix/pkgs.nix` as a local `pkgs.local` alias; it is not a feature
and does not register modules by itself.

```nix
pkgs.local.noctaliaDesktop = import ../packages/noctalia-desktop { pkgs = final; };
# pkgs.local.noctaliaDesktop.{noctalia,luciole,umbriel,noctalia-greeter,portal}
```

## Provenance

| Attribute | Upstream package | Version | Source |
| --- | --- | --- | --- |
| `noctalia` | `noctalia-dev/noctalia` | 5.6.0 (tag `v5.6.0`, 2026-11-20) | `fetchFromGitHub`, rev `a5444b9a2c2bc7c1aed5c59298a268e45de14055`, hash `sha256-3Bt4df3TM7shQGxQbSDBjYk74oemNvRl4KT3DmLZGF4=`; recipe adapted from upstream `nix/package.nix` at the tag |
| `umbriel` | `noctalia-dev/umbriel` | 0-unstable-2026-11-24 | `fetchFromGitHub`, rev `b56b66ce66b4cf84d34e522d3ad63a82b215ccd9`, hash `sha256-Pfnu8U7taFHVr88V6dK6LOR+ANCOgfVCVn4aQ7DVUsc=`; recipe adapted from upstream `nix/package.nix` (nixpkgs copy is 0a22bd2 / 2026-11-09) |
| `noctalia-greeter` | `noctalia-dev/noctalia-greeter` | 1.7.1 (tag `v1.7.1`, 2026-11-22) | `fetchFromGitHub`, rev `2726e75375d95d5458d021f76c330ab14f6a5d03`, hash `sha256-6ojA9tFyaZO+jczG0KCP42xvCMbKVd5WLaAWvc5QGjA=`; nixpkgs-unstable recipe is 1.7.0 |
| `luciole` | `noctalia-dev/luciole` | 0.1.0 (latest `main`) | `fetchFromGitHub`, rev `95ccd465b24e616bbcf05a6d753e1e75b7432310`, hash `sha256-Fd+LQSDITobK36lH9/tvzzQNODVCcf2m+YEtrIThGjk=`; no nixpkgs package; recipe adapted from upstream `nix/package.nix` |
| `portal` | `noctalia-dev/xdg-desktop-portal-umbriel` | 0.1.0 (latest `main`) | `fetchFromGitHub`, rev `426d3d433d5a738d4abf01474c34487f884396ae`, hash `sha256-e9WsUzb8MxS4PtIt9ES87j0/fdvxO75Y/StvI8Ed1SQ=`; upstream recipe updated for the noctalia-ui share picker (no GTK4) |

`noctalia-greeter` and `xdg-desktop-portal-umbriel` are also exposed under their
upstream attribute names.

## Modules

`modules/noctalia/` holds verbatim copies of upstream `nix/{home-module,nixos-module,hjem-module}.nix`
from tag `v5.6.0`. They are plain module files (`programs.noctalia.*`). The
Home Manager module defaults `programs.noctalia.package` to `pkgs.noctalia`
(nixpkgs-unstable 5.4.1), so a caller must set it to `noctaliaDesktop.noctalia`.
The NixOS module disables nixpkgs' `programs/wayland/noctalia.nix` (which exists
in nixpkgs-unstable 26.11) to avoid duplicate option definitions.

Umbriel, Luciole and the portal ship their own NixOS/Home Manager modules in
their upstream repositories; see `.work/research/noctalia-pkgs-status.md` for the
file paths and the wiring they expect.
