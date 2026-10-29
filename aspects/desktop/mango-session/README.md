# Mango session

Provides the Mango Wayland desktop and its Noctalia shell integration. Inputs are `user.appearance`, host display facts, selected `noctaliaIntegrations`, and the public `nixDotfiles.graphicalSessionTargets` option from session support.

Outputs include Mango/Noctalia configuration, clipboard bridges, screenshot and OCR tools, per-session environment, and host-side Mango/portal modules routed through `interactive-session-host`. The `noctaliaIntegrations` quirk is declared here and validated by `contract.nix`. This feature owns its session target and Noctalia service lifecycle; it does not select the login greeter. Home Manager follows the NixOS rebuild.

## Bar and Dock (r37b)

The approved G1/G2 design replaces the dense HUD with a flush 30 logical pixel top bar. Its surface has opacity 0.62, no outline, corners, outer margins or shadow. Inter 500 and native Tabler glyphs are used throughout; the active application name uses weight 650. The left section contains a grid launcher, application name and native `focus_hint` workspaces without numbers or app icons. The center stays empty. The right contains the pinned Fcitx tray indicator/drawer, network, Bluetooth, icon-only volume, neutral native battery glyph/percentage, unread-only notifications, sliders control-center button and Chinese date/time. The native control-center widget has no unread badge; a small native notifications widget appears only while unread history exists. There is no permanent sysmon, layout label, keymode label, tools accordion or capsule group.

`active-app-name.patch` adds opt-in `widget.active_window.show_app_name`, and accepts the intermediate Pango weight 650 in the shared widget selector, resolving the application through Noctalia's existing desktop identity resolver (the same one used by Dock). Unmatched applications fall back to their app ID, never their window/document title. The Neovim desktop entry (`kitty --class=Neovim nvim`) makes its identity explicit.

The floating bottom Dock uses native Smart auto-hide: empty workspace shows it, occupied workspace hides it, and the bottom edge reveals it again. `reserve_space=false` means its exclusive zone is zero. `layer=overlay` keeps the reveal strip and Dock reachable over fullscreen clients. It uses 44 px icons, 8 px edge gap, 16 px corners, opacity 0.80, native running dots and active accent, a leading grid launcher, and restrained 1.2× magnification. Dock client shadow is disabled: isolated Mango tests with both Pixman and GLES2 showed a thick black fringe when client shadow and native layer blur were combined; the fine capsule outline stays. Pinned order is kitty, firefox, obsidian, thunar, code, qq, musicfox; running apps are added natively. The launcher's application icons retain their source colors (`app_icon_colorize=false`); Dock also uses native application icons rather than replacing them with hand-drawn glyphs.

Both surfaces request `compositor_blur=true`. Locked Mango 0.18.3 does not implement `ext-background-effect-v1`; its native blur supplies the actual effect. Blur and layer blur are enabled with optimized wallpaper caching, radius 5 and two passes. Ordered `layer_rule` entries first disable blur everywhere, then enable it only for `noctalia-bar-*` and `noctalia-dock`. A catch-all window rule keeps normal clients unblurred. Panels, notifications and OSD remain solid with their existing single outlines. The bar reserves exactly its own height; native floating panels follow the usable edge plus 12 px. Notifications use their native usable-edge positioning plus 12 px (the old absolute-edge SYSTEM-tooltip avoidance is gone). OSD stays bottom-center with a 96 px offset so even a revealed Dock remains below it.

### Function entry points

| Previous bar entry | Current entry |
| --- | --- |
| CPU/MEM/GPU/temperature SYSTEM hover | Control Center → System shortcut or sidebar; full native graphs/details; `Super+Alt+M` still toggles btop |
| Brightness | Control Center Home slider and Monitor tab; hardware keys remain |
| Power profile / caffeine | Control Center Home shortcuts; `Super+Alt+I` toggles caffeine |
| Quill status / tools drawer | Control Center Home Quill shortcut (live notes/due state) and Quill panel; launcher `/nt` remains |
| Docker | `Super+Ctrl+D` opens native Mini Docker manager with container status/actions; launcher Panels provider also lists it |
| portctl | `Super+Ctrl+P` opens native port panel with live listeners/actions; launcher Panels provider also lists it |
| Tile / layout button | `Super+W` cycles Mango layout; `Super+Ctrl+W` opens the existing layouts panel |
| Keymode label | Native `Super+R` resize mode and its existing exit bindings; `Super+F1` shows key help |
| Notifications | Control Center Notifications tab / Home DND shortcut; small bar icon appears only when unread |
| Battery conservation | Battery left click still runs `legion-conservation toggle`; local conservation plugin remains enabled |

Control Center uses compact sidebar navigation so System, Monitor, Power, Notifications and other tabs remain discoverable. Its six Home shortcuts are System, power profile, caffeine, Quill, DND and nightlight. Native network/Bluetooth/audio bar buttons open their detailed tabs. Existing hooks, services, secrets and application data are preserved.

## Source patches

The package overrides only the locked `pkgs.local.noctalia` derivation. Every retained/new patch has source drift assertions in `noctalia.nix`; `interactive-session-config` validates the actual generated TOML using the built Noctalia binary and asserts the serialized bar/Dock contract.

| Patch | Purpose |
| --- | --- |
| `astra-selection.patch` | Launcher/shortcut selection styling and compact vertical Control Center Home with volume/brightness sliders; old workspace and media-widget changes removed |
| `tech-lockscreen.patch` | Existing palette password underline, user/host/kernel/battery footer and Legion maintenance readout |
| `tech-osd-segments.patch` | Existing twenty-segment progress feedback, monospace value and safe scene-tree rebuild |
| `nvidia-sampler.patch` | System-service portions extracted from old hud-sysmon: NVIDIA-only two-second sampling, suspended/unplugged GPU invalidation and short NVML sessions |
| `active-app-name.patch` | Opt-in application-name label using native identity resolution |

All eight `hud-*` patches are removed: old bar/workspace decorations, bespoke tooltip payload/renderer, battery renderer, control tooltips, sysmon drawings/threshold options, balanced readouts, centered-clock/drawer clearance and SYSTEM-toast coordination. Their build-time markers, runtime assertions and standalone overlay-clearance test are removed too. Battery rendering and low-discharge warning now follow upstream glyph mode. No source patch changes Dock, workspaces or notification badge rendering.

Legion conservation remains supplied by the local status plugin and the separately owned `hardware/legion-laptop` command. Its readout prefers ideapad_acpi, then standard `charge_control_end_threshold`, and reports unavailable state explicitly. Notification history, encryption migrations and lockscreen validation belong to upstream Noctalia 5.4.

Plugin sources remain pinned by `flake.lock`; runtime plugin state is preserved. The community overlay retains its `community` identity and untouched plugin symlinks. Existing local translations and compact widget renderers remain available if manually selected, but their widgets are absent from the declared bar. Quill continues to use the Go backend and launcher provider. `nix-search-tv` and `fzf` remain supplied for the independent launcher search plugin.

## Ownership and removal

`default.nix` and `contract.nix` are public. `mango.nix`, `noctalia.nix`, `noctalia/`, `clipboard.nix`, `screenshot.nix`, `tesseract-ocr.nix`, and `host/` are private implementation. `checks.nix` is the explicit public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` as needed.

HM owns the generated Mango/Noctalia configurations, palette, pinned Neovim desktop entry and Noctalia unit. The pre-start ownership helper backs up and reconciles only declared public override paths; it does not edit unknown runtime state. The unit sets `LC_TIME=zh_CN.UTF-8`. Removing this feature withdraws configuration and services on the next activation, while preserving documents, notes, histories, settings outside declared paths and other user state. It does not switch or stop the running session during a build.

HM owns `Pictures/Wallpapers/managed` as a store link. The activation only creates a missing `Pictures/Wallpapers/local/`, preserves directories and directory symlinks, and rejects other existing objects without replacement. Native scanning follows directory symlinks with canonical-path deduplication; local images stay outside Git/store. The five managed wallpapers remain 002/005/008/009/011, defaulting to 005; native startup/daily random rotation pauses during fullscreen. Lockscreen follows the current wallpaper; greeter uses the factory default.

## Windows and pointer

The single private window-rule table is `mango/window-rules.nix`, imported by `mango.nix`. `interactive-session-config` runs locked Mango's parser and generated-rule matching/false-positive fixtures. Main chats, browser windows and application placement stay user-controlled. Native transients float; exact chooser titles, polkit/pinentry, media/PiP, temporary settings and named scratch tools retain their established rules. Optional `assignAppTags` remains off. Proprietary runtime app IDs/titles require real-session acceptance.

Mango still uses 12 px outer / 8 px inner gaps, 10 px client corners and a native 2 px focus border. Only floating clients receive shadows; inactive clients have 6.3% dim and fullscreen is exempt. Opens/moves/tag changes use 180 ms, closes 160 ms and the existing ease-out curve; `reducedMotion` disables animation. `focus_on_activate=0` prevents unsolicited activation jumps. Tearing remains restricted to fullscreen games by the existing rules. These choices are based on locked Mango 0.18.3 sources, not newer documentation.

Fcitx keeps `ClassicUI.PreferTextIcon=True` and the bar's pinned `fcitx` SNI, so the native tray image can express Rime's Chinese/English submode. No polling service or synthetic real-session keys are added. phinger-cursors-light 32 remains shared by Mango, HM session environment, GTK, Xresources and Xorg; at 1.5 scale this is nominally 48 device pixels.

Build-time validation, isolated sway/Mango screenshots and activation are separate evidence levels. Headless sway can verify layout and layer-shell behavior but provides no blur; actual GPU blur quality, real tray submode changes, external outputs and application focus/launch require the main agent's real-session acceptance after applying the generation.
