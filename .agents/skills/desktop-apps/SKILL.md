---
name: desktop-apps
description: Configure desktop app theming, MIME defaults, and host-specific GTK, Qt, Thunar, media, browser, and messaging integrations.
---

# Desktop applications

Use this skill for graphical application configuration in `modules/home/base/`, `modules/home/programs/apps/`, and the related system modules. Noctalia owns the live palette; Home Manager supplies app-specific defaults and bridges that the theme renderer cannot manage.

Before changing an app option, identify who owns the config file and whether the application rewrites it. Keep user-mutable files out of read-only symlinks; activation seeds should preserve existing content and handle each file independently. Confirm current package versions and generated desktop IDs in the local flake configuration.

Read the relevant reference:

- For palette flow, GTK/Qt setup, fonts, and mutable theme files, read [themes and file ownership](references/themes-files.md).
- For MIME defaults, Thunar custom actions, and clipboard payloads, read [defaults and Thunar](references/defaults-thunar.md).
- For mpv, zathura, Zen, QQ, or WeChat behavior, read [media and messaging](references/media-messaging.md).

Treat historical measurements as dated evidence. In particular, re-check an app's current protocol and portal requests before changing Wayland/XWayland flags or concluding a sharing path is impossible. Report code defects discovered during this work, but keep fixes within the user's requested scope.
