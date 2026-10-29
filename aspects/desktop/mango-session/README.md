# Mango session

Provides the Mango Wayland desktop and its Noctalia shell integration. Inputs are `user.appearance`, host display facts, selected `noctaliaIntegrations`, and the public `nixDotfiles.graphicalSessionTargets` option from session support.

Outputs include Mango/Noctalia configuration, clipboard bridges, screenshot and OCR tools, per-session environment, and host-side Mango/portal modules routed through `interactive-session-host`. The `noctaliaIntegrations` quirk is declared here and validated by `contract.nix`. This feature owns its session target and Noctalia service lifecycle; it does not select the login greeter. Home Manager follows the NixOS rebuild.

## Bar and Dock (r39)

The approved G1/G2 design replaces the dense HUD with a flush 30 logical pixel top bar. Its surface has opacity 0.62, no outline, corners, outer margins or shadow. Inter 500 and native Tabler glyphs are used throughout; the active application name uses weight 650. The left section contains a monochrome NixOS system-menu icon, application name and native `minimal` C2 workspace numbers with a white active dot, no capsule, and native-model hover cards. The center stays empty. The right contains the pinned Fcitx tray indicator/drawer, network, Bluetooth, icon-only volume, neutral native battery glyph/percentage, unread-only notifications, sliders control-center button and Chinese date/time. The native control-center widget has no unread badge; a small native notifications widget appears only while unread history exists. There is no permanent sysmon, layout label, keymode label, tools accordion or capsule group.

`active-app-name.patch` adds opt-in `widget.active_window.show_app_name`, and accepts the intermediate Pango weight 650 in the shared widget selector, resolving the application through Noctalia's existing desktop identity resolver (the same one used by Dock). Unmatched applications fall back to their app ID, never their window/document title. The Neovim desktop entry (`kitty --class=Neovim nvim`) makes its identity explicit.

The floating bottom Dock uses native Smart auto-hide: empty workspace shows it, occupied workspace hides it, and the bottom edge reveals it again. `reserve_space=false` means its exclusive zone is zero. `layer=overlay` keeps the reveal strip and Dock reachable over fullscreen clients. It uses 44 px icons, 8 px edge gap, 16 px corners, opacity 0.80, native running dots and active accent, a leading grid launcher, and restrained 1.2× magnification. Dock client shadow is disabled: isolated Mango tests with both Pixman and GLES2 showed a thick black fringe when client shadow and native layer blur were combined; the fine capsule outline stays. Pinned order is kitty, firefox, obsidian, thunar, code, qq, musicfox; running apps are added natively. The launcher's application icons retain their source colors (`app_icon_colorize=false`); Dock also uses native application icons rather than replacing them with hand-drawn glyphs.

Both surfaces request `compositor_blur=true`. Locked Mango 0.18.3 does not implement `ext-background-effect-v1`; its native blur supplies the actual effect. Blur and layer blur are enabled with optimized wallpaper caching, radius 5 and two passes. Ordered `layer_rule` entries first disable blur everywhere, then enable it only for `noctalia-bar-*` and `noctalia-dock`. The focused-output Launchpad layer additionally opts into blur by its exact namespace `noctalia-plugin:nix-dotfiles/launchpad:drawer`. A catch-all window rule keeps normal clients unblurred. Panels, notifications and OSD remain solid with their existing single outlines. The bar reserves exactly its own height; native floating panels follow the usable edge plus 12 px. Notifications use their native usable-edge positioning plus 12 px (the old absolute-edge SYSTEM-tooltip avoidance is gone). OSD stays bottom-center with a 96 px offset so even a revealed Dock remains below it.

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
| `tech-lockscreen.patch` | Compact identity/password row, circular avatar and feedback below the field |
| `tech-osd-segments.patch` | Existing twenty-segment progress feedback, monospace value and safe scene-tree rebuild |
| `nvidia-sampler.patch` | System-service portions extracted from old hud-sysmon: NVIDIA-only two-second sampling, suspended/unplugged GPU invalidation and short NVML sessions |
| `active-app-name.patch` | Opt-in application-name label using native identity resolution |
| `launchpad-native.patch` | Native application index/launch IPC, independent Dock Launchpad entry, opt-in layer capture keys and wheel events |
| `desktop-menus.patch` | Opt-in minimal active dot and workspace-model hover bridge, validated native window focus, memory-only Dock suppression, custom system-menu chrome and safe session selection |

All eight `hud-*` patches are removed: old bar/workspace decorations, bespoke tooltip payload/renderer, battery renderer, control tooltips, sysmon drawings/threshold options, balanced readouts, centered-clock/drawer clearance and SYSTEM-toast coordination. Their build-time markers, runtime assertions and standalone overlay-clearance test are removed too. Battery rendering and low-discharge warning now follow upstream glyph mode. The r39 additions change Dock launcher dispatch and opt-in C2 active-dot and native-model hover previews; notification badges retain upstream rendering.

Legion conservation remains supplied by the local status plugin and the separately owned `hardware/legion-laptop` command. Its readout prefers ideapad_acpi, then standard `charge_control_end_threshold`, and reports unavailable state explicitly. Notification history, encryption migrations and lockscreen validation belong to upstream Noctalia 5.4.

Plugin sources remain pinned by `flake.lock`; runtime plugin state is preserved. The community overlay retains its `community` identity and untouched plugin symlinks. Existing local translations and compact widget renderers remain available if manually selected, but their widgets are absent from the declared bar. Quill continues to use the Go backend and launcher provider. `nix-search-tv` and `fzf` remain supplied for the independent launcher search plugin.

## Launchpad, C2 workspaces and system menu

The local `nix-dotfiles/launchpad` plugin owns a lazy full-screen layer and a cache service. Dock's leading grid button and Super+A toggle it; Alt+Space retains the native search launcher. Escape, Super+A and blank-area clicks close the drawer. Search focuses on every open and matches names, desktop IDs and native English/localized aliases. Chinese names also match pinyin initials and full-pinyin substrings, including mixed English/Chinese names and alternate heteronym readings. The offline pronunciation table is generated by build-only pypinyin in `noctalia/local.nix`; the running plugin uses only Luau. Name matches precede initials; desktop IDs/aliases remain searchable ahead of full-pinyin substrings. Ties preserve incoming order and native usage records are untouched. Categories hide empty groups, and seven 76 px icon columns paginate with available height. Wheel and PageUp/PageDown change pages; arrows select across rows/pages; Enter and single click launch and close.

The `hidden_apps` string-list plugin setting is declared in `noctalia/plugins.nix`. Its desktop IDs suppress helper applications only while search is empty; searching still includes them. Native NoDisplay/Hidden/desktop visibility rules always apply. `app-list` reuses native desktop scanning with `zh_CN` names and version/inotify/profile-symlink invalidation. Names are deduplicated; the service preloads, refreshes asynchronously on open and every 30 seconds, and resolves at most two icon paths per callback. Failed refreshes preserve the warm cache. `app-launch` calls the original `AppProvider::activate`, retaining terminal handling, output routing, activation tokens, D-Bus activation and systemd/custom-command policy.

The API has no wallpaper blur primitive. The drawer combines `shadow/0.64` with an additional `surface/0.60` mask and exact-namespace Mango blur. This intentionally stays quiet even when a compositor supplies no blur. It covers/dims the menu bar; the Dock is temporarily suppressed through new `dock-suppress`/`dock-restore` IPC without writing settings. That suppression reason is independent of the native lockscreen-editor overlay reason. Closing, disabling or reloading the plugin restores Dock. Page dots keep 104 px of bottom clearance. Dock's launch callback is independent of the bar's system-menu action. The three local layer input/IPC extensions have build-time drift checks.

C2 uses native `minimal`, `show_labels=true`, `hide_when_empty=true`, 600-weight roughly 12 px digits, theme-muted inactive numbers, bright active number and hover ink. There is no orbit fill or slider capsule. The opt-in `active_dot` extension adds only a non-interactive white 4 px marker below the active number. Native workspace filtering, clicks and wheel behavior remain in charge.

The local `nix-dotfiles/desktop-menus` plugin receives hover snapshots from the existing workspace widget. Its bridge uses `CompositorPlatform::workspaceWindowAssignments` (the taskbar/window-switcher source, including Mango tag membership); there is no mmsg subprocess or new compositor poller. After 250 ms it positions a 314 px card below the number, clamps it inside the output, and shows icon, application identity, title and window count. An 80–120 ms pointer handoff grace keeps the card open when entering it; leaving both targets closes it. Row clicks validate the window ID against the native model and invoke native compositor focus, switching workspace. Rows use a theme-blue left strip and tint on hover; wheel keeps native workspace switching.

The top-left native launcher widget now displays the monochrome Nix snowflake SVG colorized with brightFg at about 15 px. It opens a small plugin panel with its own translucent chrome; the native panel host handles anchoring, output constraints, outside click and Escape. About opens Control Center System; Settings opens native settings. Lock/suspend use native actions. Reboot/shutdown/logout open the original session panel with the relevant entry selected; opening never arms or executes the action. Its existing click/Enter/countdown flow remains the confirmation boundary. Shortcut hints show actual bindings only (lock: Super+Alt+L).

Mango blur opt-ins are limited to bar, Dock, Launchpad, the workspace preview namespace and the system-menu namespace. Headless sway verifies layout/input and source/model wiring, not GPU blur quality or real power actions. Removing these plugins withdraws UI/configuration without deleting applications or user data; caches are in memory.

## Ownership and removal

`default.nix` and `contract.nix` are public. `mango.nix`, `noctalia.nix`, `noctalia/`, `clipboard.nix`, `screenshot.nix`, `tesseract-ocr.nix`, and `host/` are private implementation. `checks.nix` is the explicit public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` as needed.

HM owns the generated Mango/Noctalia configurations, palette, pinned Neovim desktop entry and Noctalia unit. The pre-start ownership helper backs up and reconciles only declared public override paths; it does not edit unknown runtime state. The unit sets `LC_TIME=zh_CN.UTF-8`. Removing this feature withdraws configuration and services on the next activation, while preserving documents, notes, histories, settings outside declared paths and other user state. It does not switch or stop the running session during a build.

HM owns `Pictures/Wallpapers/managed` as a store link. The activation only creates a missing `Pictures/Wallpapers/local/`, preserves directories and directory symlinks, and rejects other existing objects without replacement. Native scanning follows directory symlinks with canonical-path deduplication; local images stay outside Git/store. The five managed wallpapers remain 002/005/008/009/011, defaulting to 005; native startup/daily random rotation pauses during fullscreen. Lockscreen follows the current wallpaper; greeter uses the factory default.

## Windows and pointer

The single private window-rule table is `mango/window-rules.nix`, imported by `mango.nix`. `interactive-session-config` runs locked Mango's parser and generated-rule matching/false-positive fixtures. Main chats, browser windows and application placement stay user-controlled. Native transients float; exact chooser titles, polkit/pinentry, media/PiP, temporary settings and named scratch tools retain their established rules. Optional `assignAppTags` remains off. Proprietary runtime app IDs/titles require real-session acceptance.

Mango still uses 12 px outer / 8 px inner gaps, 10 px client corners and a native 2 px focus border. Only floating clients receive shadows; inactive clients have 6.3% dim and fullscreen is exempt. Opens/moves/tag changes use 180 ms, closes 160 ms and the existing ease-out curve; `reducedMotion` disables animation. `focus_on_activate=0` prevents unsolicited activation jumps. Tearing remains restricted to fullscreen games by the existing rules. These choices are based on locked Mango 0.18.3 sources, not newer documentation.

Fcitx keeps `ClassicUI.PreferTextIcon=True` and the bar's pinned `fcitx` SNI, so the native tray image can express Rime's Chinese/English submode. No polling service or synthetic real-session keys are added. phinger-cursors-light 32 remains shared by Mango, HM session environment, GTK, Xresources and Xorg; at 1.5 scale this is nominally 48 device pixels.

Build-time validation, isolated sway/Mango screenshots and activation are separate evidence levels. Headless sway can verify layout and layer-shell behavior but provides no blur; actual GPU blur quality, real tray submode changes, external outputs and application focus/launch require the main agent's real-session acceptance after applying the generation.


## Authentication scene (R41)

Lockscreen uses the current wallpaper with native blur/tint (0.75/0.58), Inter
clock/date and no independent seconds widget. The two managed clock widgets use 72/16px normal-weight Inter with OpenType
`tnum`; the private authentication font-size API leaves other desktop clocks
unchanged. Their managed boxes use natural text metrics. The compact login box is a transparent 400px group with a 40px
password row, reveal control and neutral arrow button. `tech-lockscreen.patch`
adds the circular 56px `~/.face` and account name above it, and moves the native
error/Caps Lock/PAM hint below it. No machine telemetry or gradient footer remains. Below 700 logical pixels the
clock/date and identity anchors move apart using actual surface dimensions, so
1280×800 at scale 1.5 does not overlap.
The appearance feature still owns missing-only avatar seeding; personal `.face`
is preserved. `lockscreen-avatar.nix` no longer adds a second sticker.

Noctalia 5.4 resolves `XDG_SESSION_ID` with login1 `GetSession` before falling back
to `GetSessionByPID`; both brightness and lock monitoring use this order. A user
service is outside the graphical logind scope. `host/mango.nix` therefore extends
Mango's early C dynamic environment list with `XDG_SESSION_ID`, before its existing
`mango-session.target` request, and clears it through the same exit list. HM's
supplementary hook imports the same variable; both modules use the same package.
No session ID is stored in Nix or added to the static whitelist. Noctalia remains
a bounded systemd user service owned by the Mango target.

logind handles lid-triggered suspend. Noctalia subscribes to `PrepareForSleep`,
locks before sleep by default and holds its sleep-delay inhibitor until the lock
surfaces are ready; Mango does not own this locking path. Native idle
`lock_and_suspend` locks before requesting suspend. Application and physical lid /
suspend / wake / actual PAM unlock still require the integrator's live test.
After deployment, log out and back in so the early hook runs; inspect
`systemctl --user show-environment` for `XDG_SESSION_ID`, then Noctalia's journal
for `logind session lock monitor active`. The integrator can run
`loginctl lock-session "$XDG_SESSION_ID"` and test lid/suspend only when prepared
to authenticate. Never run those commands during isolated visual verification.
