# Mango session

Provides the Mango Wayland desktop and its Noctalia shell integration. Inputs are `user.appearance`, host display facts, selected `noctaliaIntegrations`, and the public `nixDotfiles.graphicalSessionTargets` option from session support.

Outputs include Mango/Noctalia configuration, clipboard bridges, screenshot and OCR tools, per-session environment, and host-side Mango/portal modules routed through `interactive-session-host`. The `noctaliaIntegrations` quirk is declared here and validated by `contract.nix`. This feature owns its session target and Noctalia service lifecycle; it does not select the login greeter. Home Manager follows the NixOS rebuild.

## Bar and Dock (r39)

The approved G1/G2 design replaces the dense HUD with a flush 30 logical pixel top bar. Its surface has opacity 0.62, no outline, corners, outer margins or shadow. Inter 500 and native Tabler glyphs are used throughout; the active application name uses weight 650. The left section contains a monochrome NixOS system-menu icon, application name and native `minimal` C2 workspace numbers with a white active dot, no capsule, and native-model hover cards. The center stays empty. The right contains the inline Fcitx and application tray indicators, network, Bluetooth, icon-only volume, neutral native battery glyph/percentage, unread-only notifications, sliders control-center button and Chinese date/time. The native control-center widget has no unread badge; a small native notifications widget appears only while unread history exists. There is no permanent sysmon, layout label, keymode label, tools accordion or capsule group.

`active-app-name.patch` adds opt-in `widget.active_window.show_app_name`, and accepts the intermediate Pango weight 650 in the shared widget selector, resolving the application through Noctalia's existing desktop identity resolver (the same one used by Dock). Unmatched applications fall back to their app ID, never their window/document title. The Neovim desktop entry (`kitty --class=Neovim nvim`) makes its identity explicit.

The floating bottom Dock uses native Smart auto-hide: empty workspace shows it, occupied workspace hides it, and the bottom edge reveals it again. `reserve_space=false` means its exclusive zone is zero. `layer=overlay` keeps the reveal strip and Dock reachable over fullscreen clients. It uses 44 px icons, 8 px edge gap, 16 px corners, opacity 0.80, native running dots and active accent, a leading grid launcher, and restrained 1.2× magnification. Dock client shadow is disabled: isolated Mango tests with both Pixman and GLES2 showed a thick black fringe when client shadow and native layer blur were combined; the fine capsule outline stays. Pinned order is kitty, firefox, obsidian, thunar, code, qq, musicfox; running apps are added natively. The launcher's application icons retain their source colors (`app_icon_colorize=false`); Dock also uses native application icons rather than replacing them with hand-drawn glyphs.

Both surfaces request `compositor_blur=true`. Locked Mango 0.18.3 does not implement `ext-background-effect-v1`; its native blur supplies the actual effect. Blur and layer blur are enabled with optimized wallpaper caching, radius 5 and two passes. Ordered `layer_rule` entries first disable blur everywhere, then enable it for `noctalia-bar-*` and `noctalia-dock`. The focused-output Launchpad layer additionally opts into blur by its exact namespace `noctalia-plugin:nix-dotfiles/launchpad:drawer`. A catch-all window rule keeps normal clients unblurred. R43 extends the blur opt-in to native panels, attached panels, notifications and OSD. Their shared native Soft surface has opacity 0.80 and one outline; native panel client shadow is disabled because it creates an opaque fringe with Mango layer blur, as already observed for Dock; settings uses its native translucent-window option plus a dedicated Mango app-id blur rule. The bar reserves exactly its own height; native floating panels follow the usable edge plus 12 px. Notifications use their native usable-edge positioning plus 12 px (the old absolute-edge SYSTEM-tooltip avoidance is gone). OSD stays bottom-center with a 96 px offset so even a revealed Dock remains below it.

### Function entry points

| Previous bar entry | Current entry |
| --- | --- |
| CPU/MEM/GPU/temperature SYSTEM hover | Control Center → System shortcut or sidebar; full native graphs/details; `Super+Alt+M` still toggles btop |
| Brightness | Control Center Home slider and Monitor tab; hardware keys remain |
| Power profile / caffeine | Control Center Home shortcuts; `Super+Alt+I` toggles caffeine |
| Tile / layout button | `Super+W` cycles Mango layout; native `Super+R` enters resize mode; `Super+F1` shows key help |
| Notifications | Control Center Notifications tab / Home DND shortcut; small bar icon appears only when unread |
| Battery conservation | Battery left click still runs `legion-conservation toggle`; local conservation plugin remains enabled |

Control Center Home has no sidebar; detailed sections keep compact navigation. The visible Home width is 348 px. Wi-Fi and Bluetooth are two device tiles; System, power profile, caffeine and DND remain neutral function rows. Nightlight is disabled (`enabled=false`, `force=false`), with no Home shortcut. Native network/Bluetooth/audio bar buttons open their detailed tabs. Existing hooks, services, secrets and application data are preserved.

## Source patches

The package overrides only the locked `pkgs.local.noctalia` derivation. Every retained/new patch has source drift assertions in `noctalia.nix`; `interactive-session-config` validates the actual generated TOML using the built Noctalia binary and asserts the serialized bar/Dock contract.

| Patch | Purpose |
| --- | --- |
| `astra-selection.patch` | Launcher/shortcut selection styling and compact vertical Control Center Home with volume/brightness sliders; old workspace and media-widget changes removed |
| `tech-lockscreen.patch` | Compact identity/password row, circular avatar and feedback below the field |
| `r43-*.patch` | Independent Control Center, notification, continuous OSD, compact calendar, settings and wallpaper drawing (checked by `r43-check-panels.py`) |
| `nvidia-sampler.patch` | System-service portions extracted from old hud-sysmon: NVIDIA-only two-second sampling, suspended/unplugged GPU invalidation and short NVML sessions |
| `active-app-name.patch` | Opt-in application-name label using native identity resolution |
| `launchpad-native.patch` | Native application index/launch IPC, independent Dock Launchpad entry, opt-in layer capture keys and wheel events |
| `desktop-menus.patch` | Opt-in minimal active dot and workspace-model hover bridge, validated native window focus, memory-only Dock suppression, custom system-menu chrome and safe session selection |

All eight `hud-*` patches are removed: old bar/workspace decorations, bespoke tooltip payload/renderer, battery renderer, control tooltips, sysmon drawings/threshold options, balanced readouts, centered-clock/drawer clearance and SYSTEM-toast coordination. Their build-time markers, runtime assertions and standalone overlay-clearance test are removed too. Battery rendering and low-discharge warning follow upstream glyph mode; R44 changes only the full/pending-charge glyph to the same battery-outline-and-bolt used while charging. The r39 additions change Dock launcher dispatch and opt-in C2 active-dot and native-model hover previews; notification badges retain upstream rendering.

Legion conservation remains supplied by the local status plugin and the separately owned `hardware/legion-laptop` command. Its readout prefers ideapad_acpi, then standard `charge_control_end_threshold`, and reports unavailable state explicitly. Notification history, encryption migrations and lockscreen validation belong to upstream Noctalia 5.4.

Only the repository-owned `nix-dotfiles/launchpad`, `nix-dotfiles/desktop-menus` and `nix-dotfiles/legion-conservation` plugins are loaded, from the local Nix-built source. Community/official plugin sources, community settings, shortcuts and custom renderers are removed. The native Alt+Space launcher keeps built-in application search; it has no community provider configuration. Launchpad's hidden applications and icon overrides remain declared below.

The pre-start reconciler removes and backs up declared `plugins.enabled`, `plugins.source` and control-center shortcut overrides. Removed plugins' undeclared `plugin_settings` and `widget` tables remain in runtime state and require a separate review while Noctalia is stopped. It never deletes plugin data such as Quill notes. The unused official/community flake inputs remain locked pending integration cleanup; they are no longer referenced by this feature.

## Launchpad, C2 workspaces and system menu

The local `nix-dotfiles/launchpad` plugin owns a lazy full-screen layer and a cache service. Dock's leading grid button and Super+A toggle it; Alt+Space retains the native search launcher. Escape, Super+A and blank-area clicks close the drawer. Search focuses on every open and matches names, desktop IDs and native English/localized aliases. Chinese names also match pinyin initials and full-pinyin substrings, including mixed English/Chinese names and alternate heteronym readings. The offline pronunciation table is generated by build-only pypinyin in `noctalia/local.nix`; the running plugin uses only Luau. The generated table packs readings into 256-codepoint pages and caches indexed lookups, keeping all pronunciations while avoiding a large table-constructor AST that exceeded the locked runtime's 100 ms load budget during isolated validation. Lookups use plain substring searches; icon prewarming resolves one application per callback to stay within the separate 25 ms callback budget. Name matches precede initials; desktop IDs/aliases remain searchable ahead of full-pinyin substrings. Ties preserve incoming order and native usage records are untouched. Categories hide empty groups, and seven 76 px icon columns paginate with available height. Wheel and PageUp/PageDown change pages; arrows select across rows/pages; Enter and single click launch and close.

The `hidden_apps` string-list plugin setting is declared in `noctalia/plugins.nix`. R44 additionally suppresses Thunar Bulk Rename, removable-media settings and the Fcitx daemon launcher from the empty-query grid. Its desktop IDs suppress helper applications only while search is empty; searching still includes them. Native NoDisplay/Hidden/desktop visibility rules always apply. `app-list` reuses native desktop scanning with `zh_CN` names and version/inotify/profile-symlink invalidation. Names are deduplicated; the service preloads, refreshes asynchronously on open and every 30 seconds, and resolves at most one application icon per callback. Failed refreshes preserve the warm cache. `app-launch` calls the original `AppProvider::activate`, retaining terminal handling, output routing, activation tokens, D-Bus activation and systemd/custom-command policy.

The API has no wallpaper blur primitive. The drawer combines `shadow/0.64` with an additional `surface/0.60` mask and exact-namespace Mango blur. This intentionally stays quiet even when a compositor supplies no blur. It covers/dims the menu bar; the Dock is temporarily suppressed through new `dock-suppress`/`dock-restore` IPC without writing settings. That suppression reason is independent of the native lockscreen-editor overlay reason. Closing, disabling or reloading the plugin restores Dock. Page dots keep 104 px of bottom clearance. Dock's launch callback is independent of the bar's system-menu action. The three local layer input/IPC extensions have build-time drift checks.

C2 uses native `minimal`, `show_labels=true`, `hide_when_empty=true`, 600-weight roughly 12 px digits, theme-muted inactive numbers, bright active number and hover ink. There is no orbit fill or slider capsule. The opt-in `active_dot` extension adds only a non-interactive white 4 px marker below the active number. Native workspace filtering, clicks and wheel behavior remain in charge.

The local `nix-dotfiles/desktop-menus` plugin receives hover snapshots from the existing workspace widget. Its bridge uses `CompositorPlatform::workspaceWindowAssignments` (the taskbar/window-switcher source, including Mango tag membership); there is no mmsg subprocess or new compositor poller. After 250 ms it positions a 314 px card below the number, clamps it inside the output, and shows icon, application identity, title and window count. An 80–120 ms pointer handoff grace keeps the card open when entering it; leaving both targets closes it. Row clicks validate the window ID against the native model and invoke native compositor focus, switching workspace. Rows use a theme-blue left strip and tint on hover; wheel keeps native workspace switching.

The top-left native launcher widget now displays the monochrome Nix snowflake SVG colorized with brightFg at about 15 px. It opens a small plugin panel with its own translucent chrome; the native panel host handles anchoring, output constraints, outside click and Escape. About opens Control Center System; Settings opens native settings. Lock/suspend use native actions. Reboot/shutdown/logout open the original session panel with the relevant entry selected; opening never arms or executes the action. Its existing click/Enter/countdown flow remains the confirmation boundary. Shortcut hints show actual bindings only (lock: Super+Alt+L).

Mango blur opt-ins cover the unchanged bar, Dock, Launchpad, workspace preview and system-menu namespaces, plus R43 native panel/attached-panel/notification/OSD namespaces and the native settings app-id. Headless sway verifies layout/input and source/model wiring, not GPU blur quality or real power actions. Removing these plugins withdraws UI/configuration without deleting applications or user data; caches are in memory.

## R43 panel styling

Each panel adaptation is a separate `noctalia/r43-*.patch`: control center,
notifications, OSD, calendar, settings, and wallpaper picker. They apply after the
existing selection and shell integration patches. `r43-check-panels.py` runs at
postPatch and fails on source drift. `interactive-session-config` checks the
serialized native configuration and patch set. Global UI Style constants, bar,
Dock, Launchpad, system menu, workspaces and authentication remain independently
owned.

Native Soft surface mode is declared once beside its pinned 0.80 opacity; transient
notification and OSD backgrounds consume the same value. Labels remain opaque.
The OSD replaces the removed `tech-osd-segments.patch` with 246×46 horizontal
geometry, an 18px neutral icon, 3px continuous rail, 13px percentage and 96px bottom
offset. Notification width remains 320 with compact 13px metadata and 14px title/body.
Direct calendar opens at 320, without a navigation rail, with the month above agenda
and an independent 1px today outline (it does not rely on global button borders).
Settings keeps native categories/groups and neutral 20/14/13 typography. Wallpaper
selection uses three columns and a viewport capped to exactly two rows (760×430 panel), neutral thumbnails and
a 1px blue current/selected border with a check; the full collection still scrolls.
No wallpaper collection, rotation preference, notification timeout or user data is
removed. Removing these patches reverts drawing, not persisted application state.

## Ownership and removal

`default.nix` and `contract.nix` are public. `mango.nix`, `noctalia.nix`, `noctalia/`, `clipboard.nix`, `screenshot.nix`, `tesseract-ocr.nix`, and `host/` are private implementation. `checks.nix` is the explicit public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` as needed.

HM owns the generated Mango/Noctalia configurations, palette, pinned Neovim desktop entry and Noctalia unit. The pre-start ownership helper backs up and reconciles only declared public override paths; it does not edit unknown runtime state. The unit sets `LC_TIME=zh_CN.UTF-8`. Removing this feature withdraws configuration and services on the next activation, while preserving documents, notes, histories, settings outside declared paths and other user state. It does not switch or stop the running session during a build.

HM owns `Pictures/Wallpapers/managed` as a store link. The activation only creates a missing `Pictures/Wallpapers/local/`, preserves directories and directory symlinks, and rejects other existing objects without replacement. Native scanning follows directory symlinks with canonical-path deduplication; local images stay outside Git/store. The managed wallpaper collection remains intact (the package/check manifest has 18 images), defaulting to 005; native startup/daily random rotation pauses during fullscreen. Lockscreen follows the current wallpaper; greeter uses the factory default.

## Windows and pointer

The single private window-rule table is `mango/window-rules.nix`, imported by `mango.nix`.
`interactive-session-config` runs locked Mango's parser and both generated-rule
fixture suites (`resources/window-rules-check.py`, `mango/check-window-rules.py`).
They check allowed window/layer fields, UTF-8 value lengths, matching order,
main-window exclusions, scratchpads, PiP, silent toolbars and game exceptions.
Fixtures are policy checks, not evidence that a proprietary application's windows
were opened. Optional `assignAppTags` stays off; no app receives a fixed tag.

Rules use Mango 0.18.3, revision `9c44c664725421fbccaf2619e3641b38614db04d`:
[`option_defs.c`](https://github.com/mangowm/mango/blob/9c44c664725421fbccaf2619e3641b38614db04d/src/config/option_defs.c),
[`client.c`](https://github.com/mangowm/mango/blob/9c44c664725421fbccaf2619e3641b38614db04d/src/manage/client.c).
`app_id` is the native app ID or XWayland WM_CLASS; combining it with `title`
requires both to match. Properties merge in file order. Titles are matched when
mapping; later title changes do not rerun rules. Native transient/fixed-size
windows and X11 modal/splash/utility/toolbar windows with size hints already float.
Mango centers initial windows unless `no_force_center` is set. Width/height
between 0 and 1 are output fractions; larger values are initial logical pixels,
not enforced minimum/maximum sizes. Client hints may constrain them. Offsets are
percentages of the remaining half-screen, not pixels.

| Windows | Match / behavior |
|---|---|
| File choosers, Open/Save | Native transients plus exact English/Chinese title fallbacks scoped to browser, mail, file manager, editors, office, graphics and chat apps; centered about 1024×694 at 1707×1067 |
| Preferences/Settings/Properties, About/confirmation | App-scoped exact titles; settings about 922×683, compact dialogs about 717×405; document/tab titles with application suffixes stay tiled |
| Portal, polkit, pinentry | Portal app IDs float at chooser size; authentication IDs about 649×341; parented native dialogs retain client hints |
| Firefox | `firefox` / Library, Downloads and About float; PiP starts 480×270 near bottom right, `is_overlay` + `is_global` + silent opening |
| Thunar | `thunar` / File Operation Progress (about 717×192), properties, preferences and Bulk Rename float; main directory windows remain tiled |
| Audio/Bluetooth/network | `org.pulseaudio.pavucontrol`, `blueman-manager` / `org.blueman.Manager`, `nm-connection-editor`: about 683×598 near top right |
| CopyQ, Clash, calculator/color tools | `com.github.hluk.copyq`, `clash-verge`, calculator/color-picker IDs: floating, with separate practical sizes; no fixed tag or persistent no-focus |
| Qt/Fcitx settings | `qt6ct`, `qt5ct`, `org.fcitx.*`, `fcitx5-config-qt`; File Roller, keyboard-layout viewer and Legion controls: floating settings size; observed Fcitx ID is `org.fcitx.` |
| QQ/WeChat/Tencent Meeting/Vesktop | Distinct login, image-viewer and call titles float; passive notifications open silently; sharing-toolbar titles additionally use persistent `no_focus`; main chats stay tiled |
| JetBrains/LibreOffice/Zotero/GIMP/Prism | Agreement/splash, Prism Quick Setup and specific tool/dialog titles float (JetBrains agreements retain client size to avoid empty Wayland frames); project, document, library and image main windows stay tiled |
| Thunderbird/Obsidian/VS Code/MATLAB/OBS/Kdenlive/Blender/virt-manager | Native transients and app-scoped dialog fallbacks; compose windows, projects, VMs and other main windows keep their native behavior |
| mpv/swayimg/imv/feh, games | Players/viewers float and receive compositor opacity 1; games matching `steam_app_[0-9]+` or Minecraft keep border/shadow/radius/animation removal, fullscreen-only tearing and the existing VRR hint (the host output enables VRR globally); never force helpers fullscreen |
| Steam | Friends List narrow floating window, Settings/Login floating, notifications silent and unfocusable; main client tiled |
| Capture tools | mark-shot editor toplevel floats; capture overlays and wayscrollshot layer surfaces keep full-output geometry |
| Kitty/scratchpads | Existing Kitty frosting (`no_blur:0`), opacity and named scratch identities/sizes remain intact |

There is no Mango rule for `keep_aspect_ratio`, `opaque`, window role/type criteria,
min/max size or dynamic title matching. PiP retains client size/aspect hints, but
an arbitrary resize is not compositor-constrained to 16:9. Opacity 1 removes only
compositor-added transparency; it cannot replace pixels a client draws with alpha.
`is_global` means all tags on the owning output, not all outputs. Layer rules
match `layer_name` and only support animation types, `shield_when_capture`,
`no_blur`, `no_animation`, `no_shadow`; they cannot reposition/focus a capture layer.

Community references, inspected 2026-10-30 (behavior adapted, syntax not copied):

- [Hyprland wiki](https://github.com/hyprwm/hyprland-wiki/blob/main/content/configuring/core/rules/window-rules.md): matching, initial versus dynamic effects and fullscreen policy.
- [end-4](https://github.com/end-4/dots-hyprland/blob/2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8/dots/.config/hypr/hyprland/rules.lua): chooser/control sizing and pinned PiP. Its broad title and all-Zotero floating rules are deliberately narrowed here.
- [HyDE](https://github.com/HyDE-Project/HyDE/blob/fa2fd57afc7203b1b5653d3271f3a57ea3873f97/Configs/.local/share/hypr/lua/window_rules.lua): grouped controls, modals and PiP.
- [JaKooLit](https://github.com/JaKooLit/Hyprland-Dots/blob/c093e836764d62346390ba307c9163ca11d0229b/config/hypr/configs/WindowRules.conf): Thunar progress, settings utilities, PiP and numeric Steam game classes.
- [Sway-DE](https://github.com/madic-creates/Sway-DE/blob/ddfc746b3851ed495b027edb927915c4d00d8396/config/sway/sway.d/06_floating.conf): transient roles/types and pinentry; Mango handles supported types natively rather than exposing these criteria.
- [Mango examples](https://github.com/mangowm/mango/blob/9c44c664725421fbccaf2619e3641b38614db04d/docs/window-management/rules.md): initial sizes/offsets, game tearing and named scratchpads. The bundled `assets/config.conf` only supplies layer animation examples; parser source takes precedence over documentation tables.
- [ML4W](https://github.com/mylinuxforwork/dotfiles/blob/d6bfb5a4d2ca9fd9f0e69510b75f7aa59fe57a34/dotfiles/.config/hypr/conf/windowrules/default.lua): current default file is empty, so it supplies no additional rules. [Earlier default](https://github.com/mylinuxforwork/dotfiles/blob/437a2eb26540bc66215f6a3a53af959095b5dc6d/dotfiles/.config/hypr/conf/windowrules/default.conf) contains optional commented examples, not a reason to force a global XWayland workaround.

R45 isolation uses real headless Mango, private HOME/XDG/socket/D-Bus and per-app
mount/PID/network namespaces. It never opens existing profiles or starts user
session services. Screenshots/IPC observations are separate from configuration
application. In the installed QQ build, the login is `QQ` / `QQ`; WeChat login is
XWayland `wechat` / `Weixin`. Mango cannot distinguish them from a main window
with the same identifiers. No unconditional floating rule is applied to these ambiguous IDs (WeChat may
float natively through fixed-size hints); `Super+Space`
provides the existing manual floating toggle. Distinct login-title fallbacks are
conditional, not a claim that post-login chat/call/share windows were observed.

Mango still uses 12 px outer / 8 px inner gaps, 12 px client corners and a native 1 px blue focus border. Only floating clients receive shadows; inactive clients have 6.3% dim and fullscreen is exempt. Opens/closes/tag changes use 140/110/150 ms, moves 180 ms, focus 0 ms, and the existing ease-out curve; opening zoom begins at 0.985; `reducedMotion` disables animation. `focus_on_activate=0` prevents unsolicited activation jumps. Tearing remains restricted to fullscreen games by the existing rules. These choices are based on locked Mango 0.18.3 sources, not newer documentation.

Fcitx keeps `ClassicUI.PreferTextIcon=True` and the bar's pinned `fcitx` SNI, so the native tray image can express Rime's Chinese/English submode. No polling service or synthetic real-session keys are added. Bibata-Modern-Ice 24 (nixpkgs bibata-cursors) is shared by Mango, HM session environment, GTK, Xresources and Xorg; at 1.5 scale this is nominally 36 device pixels.

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

## R44 desk corrections (2026-10-29)

Bibata-Modern-Ice from `bibata-cursors` replaces the previous pointer at 24 logical px (nominally 36 device px at scale 1.5; 32 looked oversized). Shared appearance, HM GTK/Xresources/environment, Mango, Xorg and greeter all consume that theme and size; greeter also installs the matching package. Qt inherits the shared cursor environment and Xresources, with no additional GUI settings migration.

Tray items render inline (`drawer=false`), which removes the attached reverse-corner capsule for the usual one or two application items. Native symbolic icons retain brightFg tint; application colour artwork remains intact. Tray, network, Bluetooth, volume, battery, unread notification and control-center use a common 18 logical px box (`scale=1.125` against native 16). The bar explicitly sets `icon_color=brightFg`; disconnected network/Bluetooth and muted audio use secondary grey. Network/Bluetooth retain the locked Tabler shapes and native state models. Battery charging, full and pending-charge/charge-limit states use `battery-charging`, with the native percentage and original low-battery threshold/colour preserved. `r44-status-icons.patch` and its build-time source checks fail closed on upstream drift. The resolver also checks hicolor `1024x1024/apps` when theme indexes omit that directory; this fixes the real DeepSeek Harness fallback.

Launchpad's `icon_overrides` string list accepts `desktop-id=icon-name-or-absolute-path`; it changes artwork only (absolute paths bypass desktop-ID fuzzy matching) and falls back to native lookup if the override is unavailable. Neovim uses its packaged upstream icon, long-task terminal uses the original `resources/terminal-clock.svg`, and the user's Dead by Daylight launcher uses its actual Steam app icon instead of the Steam logo. No desktop files, launch commands, histories or GUI state are rewritten. `resources/dead-by-daylight.jpg` is the unmodified 32×32 public app thumbnail from Steam's library cache for app 381210 (Behaviour Interactive artwork; SHA256 `2f308ff02f87f002d757a24f54e590118ad3e13ac5e860a3fe2bd5f25af5de93`). Yazi and Legion GUI already resolve their package pixmaps and retain them.

The complete host desktop/icon audit and private Sway shots are under `.work/r44/desk/`. They verify rendering at 2560×1600/scale 1.5 with synthetic private D-Bus devices, not application of this worktree or physical hardware transitions. Removal withdraws these package/settings/plugin assets and leaves user desktop entries and application data intact.

## R50 blur edge sampling

Mango's locked scenefx (`37ccd723bef49e6891156ffafce8f549f01446cc`)
uses full-output-size ping-pong FBOs for the dual-Kawase pyramid. Each reduced
level populates only its top-left rectangle. `GL_CLAMP_TO_EDGE` is already set
in `render/fx_renderer/fx_texture.c`, but protects the whole allocation rather
than that rectangle. Upsample taps at its right/bottom boundary can therefore
read stale pixels from a previous pass. A bright-center/dark-right wallpaper
reproduces the right-edge light band in isolated Mango at 2560×1600, scale 1.5.
This is a reduced-level sampling defect, not evidence of `GL_REPEAT` or a
Noctalia bar width mismatch; fractional scaling exposes it in the reported setup.

`mango/scenefx-blur-level-clamp.patch` adds populated-level texel-center bounds
to both blur shaders; `fx_pass.c` supplies the source level for each down/up pass.
Where supported, the new sampling bounds use high precision so rounding cannot
move a texel-center limit into the stale region (the poison fixture also
detects this with mediump bounds).
`host/mango.nix` overrides only the locked Mango dependency, preserving its
wlroots package set. Radius 5, two passes, optimized wallpaper caching, bar
opacity 0.62, flush geometry and Dock opacity 0.80/radius 16/margin 8 remain.
No Noctalia source or configuration writer changes are required. Removal
withdraws the renderer patch on the next compositor restart and touches no state.

`mango-blur-sampling` renders the actual upstream and patched fragment shaders
through surfaceless Mesa GLES with deliberately poisoned unused FBO regions.
It checks edge color differences and preservation of blur at the physical
2560×1600 size and an odd-size fixture. This sandboxed shader regression does
not start a compositor or connect to a desktop session. Full compositor and
Noctalia screenshots are a separate isolated runtime check; `grim -s 1`
resamples the 2560×1600 output to 1707×1067, so the final row/column can have
resampling alpha and should also be inspected in `grim -s 1.5` physical pixels.
Apply the built system through the normal main-agent workflow and log out/in
before checking the new Mango renderer on the real display.
