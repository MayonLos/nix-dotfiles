# noctalia-desktop

Package factory for the two Noctalia components this repository uses (2026-11).
Consumed from `nix/pkgs.nix` as a local `pkgs.local` alias; it is not a feature
and does not register modules by itself.

```nix
pkgs.local.noctaliaDesktop = import ../packages/noctalia-desktop { pkgs = final; };
# pkgs.local.noctaliaDesktop.{noctalia,greeter}
```

## Provenance

| Attribute | Upstream package | Version | Source |
| --- | --- | --- | --- |
| `noctalia` | `noctalia-dev/noctalia` | 5.6.0 (tag `v5.6.0`, 2026-11-20) | `fetchFromGitHub`, rev `a5444b9a2c2bc7c1aed5c59298a268e45de14055`, hash `sha256-3Bt4df3TM7shQGxQbSDBjYk74oemNvRl4KT3DmLZGF4=`; recipe adapted from upstream `nix/package.nix` at the tag |
| `noctalia-greeter` | `noctalia-dev/noctalia-greeter` | 1.7.1 (tag `v1.7.1`, 2026-11-22) | `fetchFromGitHub`, rev `2726e75375d95d5458d021f76c330ab14f6a5d03`, hash `sha256-6ojA9tFyaZO+jczG0KCP42xvCMbKVd5WLaAWvc5QGjA=` |

`greeter` and `noctalia-greeter` are the same derivation.

## Removed with the Umbriel session

`umbriel`, `luciole` and `xdg-desktop-portal-umbriel` were removed on
2026-11-27 together with the experimental session. Their pinned sources remain
in Git history; any user data under `~/.local/share/umbriel` or
`~/.local/share/luciole` is not touched by Nix. The verbatim upstream
NixOS/Home Manager module copies were also removed as unused: the repository's
hand-written `aspects/desktop/noctalia-shell` module and the greeter feature
own the wiring.
