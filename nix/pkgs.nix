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
        config.allowUnfree = true;
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
          })
          (final: _: {
            # Local programs have a separate public entry; local remains upstream aliases.
            bilitui = import ../packages/bilitui { pkgs = final; };
            mayonTui = import ../packages/mayon-tui { pkgs = final; };
            mayonVoice = import ../packages/mayon-voice { pkgs = final; };
            # Wayland layer-shell clipboard history and text launcher. Its
            # binary entry points are mayon-overlay / mayon-clipboard /
            # mayon-launcher; key bindings are wired by the desktop feature.
            mayonOverlay = import ../packages/mayon-overlay { pkgs = final; };
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
              # JDK 26 is absent from stable 26.05.
              jdk26 = u.javaPackages.compiler.temurin-bin.jdk-26;
            };
            # Aliases preserve upstream derivations and their pinned build caches.
            local = {
              noctalia = inputs.noctalia.packages.${system}.default;
              # Upstream derivation alias. The mangobar flake still imports
              # the followed nixpkgs-unstable while producing this package.
              mangobar = inputs.mangobar.packages.${system}.default;
              # Vendored Rust tree. rust-toolchain.toml pins 1.99.1; stable rustc
              # is 1.95.0 and this unstable instance provides rustc 1.99.1.
              # System libraries stay on `final` (stable).
              mark-shot = import ../packages/mark-shot {
                pkgs = final;
                inherit (u) rustc cargo;
              };
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
