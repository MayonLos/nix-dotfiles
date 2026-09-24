---
name: desktop-mango
description: Configure and troubleshoot this Mango Wayland desktop, Noctalia shell, portals, screenshots, clipboard, and fcitx5 integration.
---

# Mango desktop

Use this skill for changes or diagnosis involving the compositor, desktop session, Noctalia, greeter, portals, capture, clipboard, or input method. The active configuration is in `modules/home/wm/mango/`, `modules/home/base/`, `modules/home/services/`, and `modules/system/desktop/`.

Check the current Nix configuration and locked package source before relying on upstream docs or old measurements. Mango rejects unknown config keys at parse time, but accepted values can still have surprising runtime meaning. Validate options against the source pinned by this flake.

For Noctalia settings, validate against the installed/built Noctalia schema or binary; do not assume its example TOML matches the pinned release.

Read only the reference that matches the task:

- For Mango syntax, keybind semantics, session startup, environment, or XWayland scaling, read [compositor and session](references/compositor-session.md).
- For portal routing, screen capture, greeter startup, or screenshot selection, read [portals and capture](references/portals-capture.md).
- For fcitx5 sizing, Wayland/X11 clipboard sync, or clipboard history, read [input and clipboard](references/input-clipboard.md).

When diagnosing a client-specific issue, identify which protocol that client currently uses and inspect the relevant service or IPC state. Do not infer a universal behavior from an older measurement or from another app. Keep unrelated portal backends and session hooks intact when changing one feature.
