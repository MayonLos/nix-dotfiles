# WeChat IBus portal fix — 2026-10-25

The official WeChat 4.1.13.26 package now has an application-specific launcher forcing `QT_QPA_PLATFORM=xcb`, `QT_IM_MODULE=ibus`, and `IBUS_USE_PORTAL=1`. `im.nix` wraps the existing `pkgs.unstable.wechat` through `symlinkJoin`; it forwards every argument and rewrites only the desktop entry's executable to the absolute wrapper path. `%U`, icons and other upstream metadata remain intact. No global environment, IBus daemon, login data or chat history is changed.

## Evidence and diagnosis

The locked unstable nixpkgs revision is `02c087f3fe673c9e317f206a627cb6b910336dbe`: [recipe](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/by-name/we/wechat/linux.nix), [version data](https://github.com/NixOS/nixpkgs/blob/02c087f3fe673c9e317f206a627cb6b910336dbe/pkgs/by-name/we/wechat/sources.json). The installed Fcitx5 version is 5.1.19. Inspection of WeChat's ELF found no dynamically linked Qt dependency and found the bundled IBus implementation, `ibus-daemon`, `IBUS_USE_PORTAL`, and portal service strings. This supports the bundled/static Qt diagnosis, without asserting the exact Qt build from a version string alone.

Previous native Wayland launches lacked usable input focus. An earlier XCB + fcitx wrapper produced focus but did not enable actual Chinese input and was removed. XCB + ibus alone also failed in the current real session: the three relevant address components were accessible (matching machine-id, IBus address file, session bus), and the Fcitx PID was visible in the same PID namespace, but no IBus input context appeared.

The [Qt 5.15 IBus implementation](https://github.com/qt/qtbase/blob/5.15/src/plugins/platforminputcontexts/ibus/qibusplatforminputcontext.cpp) checks for an `ibus-daemon` executable before initializing the non-portal context. None was present in the actual WeChat process's 29 PATH directories, checked with container-aware symlink resolution. Setting `IBUS_USE_PORTAL` skips that executable discovery and connects to `org.freedesktop.portal.IBus` on the session bus, already owned by Fcitx5. This explains the missing IC more precisely than changing the address or enabling synchronous key processing. The [Fcitx Wayland guidance](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland#QT_IM_MODULE) also documents the proprietary Qt XCB + IBus route; [Fcitx's IBus frontend source](https://github.com/fcitx/fcitx5/blob/5.1.19/src/frontend/ibusfrontend/ibusfrontend.cpp) supplies the service.

## Runtime validation

A private, offline bubblewrap/Xvfb/D-Bus/Fcitx environment opened WeChat's pre-login window without accessing the user's home, session or login data. XCB + ibus alone showed no `CreateInputContext`. Adding only `IBUS_USE_PORTAL=1` caused WeChat to call `org.freedesktop.IBus.Portal.CreateInputContext("QIBusInputContext")`. This proved the connection path, not Chinese text entry, since the pre-login page lacked a usable text field.

The main agent then launched the same three-variable recipe in the real session under the user's authorization. Fcitx DebugInfo showed `program:wechat frontend:ibus focus:1`, and the user confirmed actual Chinese input and English switching both worked. No message sending was required for acceptance. The earlier unresolved-input note in `docs/neovim-rebuild-execution.md` is historical and superseded by this result.

Local evidence is retained under ignored `.work/wechat-ime-research.md`, `.work/wechat-ime-experiment/`, and `.work/wechat-ime-live/`; these are operational records, not dependencies of the configuration.

## Checks, activation and limits

`communication-wechat-ime` selects the wrapper from the actual `home.home.packages`. It replaces only the final application executable with a test probe, executes the launcher's environment and argument logic (including hostile inherited values, spaces, a URL, an empty argument and no arguments), and compares the complete desktop entry against the upstream entry with only its executable substituted. It never starts WeChat.

The launch recipe has real input acceptance evidence. The complete flake checks and system build passed, followed by a successful NixOS switch to `/nix/store/r9mz7q80fcmx0whh02a8g2rxbl9ma6b1-nixos-system-nixos-btw-26.05.20261021.da6dc0e`. The activated user profile contains the three-variable wrapper and its desktop entry points directly to it; Home Manager is active. Already running single-instance WeChat processes keep their existing environment until normally exited and relaunched. Removing the wrapper restores the upstream launch behavior without altering user data. Xwayland scaling and visual quality were not evaluated as part of this input fix. Revalidate after package or Qt changes rather than treating the workaround as universal.
