{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      u = import inputs.nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Host instantiation and every consumer share these two per-system instances.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          # nixpkgs 2026-11-22 marks CLion 2026.2.4.1 insecure: CVE-2026-111497
          # is fixed in 2026.3.0.1, which is not packaged in either channel yet.
          # The jetbrains feature keeps CLion for C/C++ and embedded work, and
          # the wrapper (`...-skiko-fix`) inherits the same meta, so both names
          # are needed. Drop this list once jetbrains.clion reaches 2026.3.0.1.
          permittedInsecurePackages = [
            "clion-2026.2.4.1"
            "clion-2026.2.4.1-skiko-fix"
          ];
        };
        overlays = [
          # xdg-desktop-portal-wlr is what serves ScreenCast under mango.
          # Stable is 0.8.2; 0.8.3 took over driving the PipeWire graph and
          # 0.8.4 fixed streams freezing on PipeWire buffer starvation --
          # both squarely in the "screen share dies after a while" class.
          #
          # It has to be an overlay rather than a package option:
          # nixos/modules/config/xdg/portals/wlr.nix hardcodes
          # `pkgs.xdg-desktop-portal-wlr` for BOTH the extraPortals entry
          # and the systemd ExecStart it overrides, and mango's own module
          # adds the same attribute again. Listing an unstable copy
          # alongside would put two different versions of one backend on the
          # bus. Taken from the same unstable instance above,
          # not a second legacyPackages evaluation.
          (_: _: {
            inherit (u) xdg-desktop-portal-wlr;
          })
          (final: previous: {
            gamemode = import ../packages/gamemode {
              inherit (previous) gamemode;
              inherit (final) runCommandCC;
            };
            # tumbler 4.20.1 installs D-Bus service files named after the Xfce
            # vendor prefix while the bus name is org.freedesktop.thumbnails.*;
            # dbus-broker warns about every mismatch. Rename the files only.
            tumbler = previous.tumbler.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                for n in Cache1 Manager1 Thumbnailer1; do
                  mv "$out/share/dbus-1/services/org.xfce.Tumbler.$n.service" \
                    "$out/share/dbus-1/services/org.freedesktop.thumbnails.$n.service"
                done
              '';
            });
          })
          (final: _: {
            # Local programs have a separate public entry; local remains upstream aliases.
            bilitui = import ../packages/bilitui { pkgs = final; };
            mayonTui = import ../packages/mayon-tui { pkgs = final; };
            mayonVoice = import ../packages/mayon-voice { pkgs = final; };
            # Explicit exceptions to stable; each consumer uses this shared instance.
            unstable = {
              # unstable: Neovim 0.12.6 fixes TUI/runtime issues after stable 0.12.4.
              inherit (u) neovim-unwrapped;
              # New official QQ release and its compatibility fixes.
              inherit (u) qq;
              # Stable still has the older official Linux client.
              inherit (u) wechat;
              # Stable CodeCompanion 19.13 lacks the ACP fixes; the editor uses the reviewed v20 API.
              codecompanion-nvim = u.vimPlugins.codecompanion-nvim;
              # Unstable provides the Legion 0.1.4 fan-table fix (83DG/NMCN).
              # Its kernel is the same 6.18.63 release as stable; boot.nix
              # asserts that before using the kernel module.
              inherit (u) lenovo-legion;
              lenovo-legion-module = u.linuxPackages.lenovo-legion-module;
              linuxKernelVersion = u.linuxPackages.kernel.version;
              # JDK 26 is absent from stable 26.05.
              jdk26 = u.javaPackages.compiler.temurin-bin.jdk-26;
            };
            # Aliases preserve upstream derivations and their pinned build caches.
            local = {
              # Upstream v0.2.4 source plus repository patches (Mango window
              # rectangles, physical pixel grid, config recovery, One Dark).
              # rust-toolchain.toml pins 1.99.1; stable rustc is 1.95.0 and this
              # unstable instance provides rustc 1.99.1. System libraries stay
              # on `final` (stable).
              mark-shot = import ../packages/mark-shot {
                pkgs = final;
                inherit (u) rustc cargo;
              };
              # Experimental Noctalia desktop stack (work/noctalia-desktop):
              # Noctalia 5.6.0, Umbriel, Luciole and the Umbriel portal, each
              # pinned to an upstream revision inside the package factory.
              # They build against the unstable instance: 5.6.0 and Luciole
              # need stb_image_resize2.h / wayland-protocols >= 1.49, which
              # stable 26.05 does not have yet. The system itself stays stable.
              noctaliaDesktop = import ../packages/noctalia-desktop { pkgs = u; };
              inherit (inputs.llm-agents.packages.${system})
                dsh
                herdr
                grok
                grok-bot
                # Google Antigravity desktop (`antigravity`) and CLI (`agy`).
                antigravity-hub
                antigravity-cli
                ;
            };
          })
        ];
      };
    };
}
