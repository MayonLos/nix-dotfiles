{ inputs, config, ... }: {
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      nixos = config.flake.nixosConfigurations.nixos-btw.config;
      home = nixos.home-manager.users.mayon;
      appearance = import ../aspects/appearance/appearance/onedark.nix;
      args = {
        inherit
          pkgs
          lib
          system
          nixos
          home
          appearance
          ;
      };
      # Public feature hooks, explicitly registered. No module discovery.
      registry = [
        ../aspects/apps/firefox/checks.nix
        ../aspects/apps/documents/checks.nix
        ../aspects/apps/communication/checks.nix
        ../aspects/apps/file-manager/checks.nix
        ../aspects/apps/media/checks.nix
        ../aspects/apps/voice-input/checks.nix
        ../aspects/apps/gaming/checks.nix
        ../aspects/apps/gaming/runtime-checks.nix
        ../aspects/cli/keys-mayon/checks.nix
        ../aspects/cli/shell/checks.nix
        ../aspects/cli/herdr/checks.nix
        ../aspects/desktop/mango-session/checks.nix
        ../aspects/desktop/greeter/checks.nix
        ../aspects/desktop/session-support/checks.nix
        ../aspects/desktop/xorg-session/checks.nix
        ../aspects/dev/embedded/checks.nix
        ../aspects/dev/containers/checks.nix
        ../aspects/dev/neovim/checks.nix
        ../aspects/dev/vscode/checks.nix
        ../aspects/hardware/legion-laptop/checks.nix
        ../aspects/network/laptop-network/checks.nix
        ../aspects/workspace/project-workbench/checks.nix
      ];
      featureChecks = builtins.foldl' (acc: path: acc // import path args) { } registry;
      embedded = import ../tests/composition/embedded.nix { inherit inputs pkgs; };
      # Evaluate only registrations here, never instantiate another host.
      registrations =
        (inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } {
          imports = [
            inputs.den.flakeModule
            ../aspects
          ];
        }).config.den.aspects;
      architecture = import ../tests/architecture {
        inherit lib;
        root = ../.;
        unstableNames = builtins.attrNames pkgs.unstable;
        # Pipeline inspection derives the whitelist from the actual overlay.
        unstableInspectors = [ "nix/checks.nix" ];
        evaluatedAspectIds = builtins.attrNames registrations;
        publicFiles = [
          "aspects/appearance/appearance/onedark.nix"
          "aspects/appearance/appearance/ansi.nix"
          "aspects/appearance/appearance/resources/wallpaper"
          "aspects/dev/neovim/package.nix"
          "aspects/desktop/session-support/qt-style.nix"
          "aspects/desktop/xorg-session/dwm/package.nix"
        ]
        ++ map (path: lib.removePrefix "${toString ../.}/" (toString path)) registry;
      };
      paletteColors = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = appearance.${name};
          })
          [
            "bg"
            "deep"
            "surface"
            "selection"
            "fg"
            "brightFg"
            "muted"
            "blue"
            "cyan"
            "green"
            "orange"
            "red"
          ]
      );
      paletteContrast =
        pkgs.runCommand "palette-contrast-check"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cat > palette.json <<'JSON'
            ${builtins.toJSON paletteColors}
            JSON
            if python3 - <<'PY' > "$TMPDIR/palette-contrast-report"
            import json
            import sys

            with open("palette.json", encoding="utf-8") as source:
                palette = json.load(source)

            def rgb(value):
                value = value.removeprefix("#")
                return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))

            def luminance(color):
                linear = tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in color)
                return sum(weight * value for weight, value in zip((0.2126, 0.7152, 0.0722), linear))

            def contrast(foreground, background):
                first, second = sorted((luminance(foreground), luminance(background)), reverse=True)
                return (first + 0.05) / (second + 0.05)

            def blend(foreground, background, alpha):
                return tuple(f * alpha + b * (1 - alpha) for f, b in zip(foreground, background))

            checks = []
            for background in ("bg", "deep", "surface", "selection"):
                checks.append((f"brightFg/{background}", rgb(palette["brightFg"]), rgb(palette[background]), 7.0))
                checks.append((f"fg/{background}", rgb(palette["fg"]), rgb(palette[background]), 4.5))
            checks.extend([
                ("blue/selection", rgb(palette["blue"]), rgb(palette["selection"]), 4.5),
                ("muted/bg", rgb(palette["muted"]), rgb(palette["bg"]), 4.5),
                ("muted/deep", rgb(palette["muted"]), rgb(palette["deep"]), 4.5),
            ])
            for foreground in ("cyan", "blue", "green", "orange", "fg"):
                checks.append((f"{foreground}/deep syntax", rgb(palette[foreground]), rgb(palette["deep"]), 7.0))
            for tint in ("green", "red", "blue"):
                for alpha in (0.08, 0.12):
                    mixed = blend(rgb(palette[tint]), rgb(palette["deep"]), alpha)
                    checks.append((f"brightFg/{tint} {int(alpha * 100)}% over deep", rgb(palette["brightFg"]), mixed, 7.0))
            white = (1.0, 1.0, 1.0)
            translucent_bg = blend(rgb(palette["bg"]), white, 0.98)
            checks.extend([
                ("brightFg/bg 98% over white", rgb(palette["brightFg"]), translucent_bg, 7.0),
                ("fg/bg 98% over white", rgb(palette["fg"]), translucent_bg, 4.5),
            ])

            failed = False
            for name, foreground, background, minimum in checks:
                ratio = contrast(foreground, background)
                passed = ratio >= minimum
                print(f"{'PASS' if passed else 'FAIL'} {name}: {ratio:.2f}:1 (required {minimum:.1f}:1)")
                failed |= not passed
            if failed:
                sys.exit(1)
            PY
            then
              status=0
            else
              status=$?
            fi
            cat "$TMPDIR/palette-contrast-report"
            if [ "$status" -ne 0 ]; then
              exit "$status"
            fi
            cp "$TMPDIR/palette-contrast-report" "$out"
          '';
      source = builtins.path {
        path = ../.;
        name = "treefmt-source";
        filter =
          path: _:
          let
            name = builtins.baseNameOf path;
          in
          !(builtins.elem name [
            ".git"
            ".work"
            ".team"
            ".worktrees"
          ])
          && !(lib.hasPrefix "result" name);
      };
    in
    {
      treefmt.projectRoot = source;
      # Force during evaluation: flake check --no-build must reject violations.
      checks = builtins.deepSeq architecture (
        featureChecks
        // {
          mayon-tui =
            assert lib.assertMsg (builtins.all
              (output: builtins.elem output.outPath (map (package: package.outPath) home.home.packages))
              [
                pkgs.mayonTui.clash
                pkgs.mayonTui.tools
              ]
            ) "TUI outputs must be installed by their selected features";
            pkgs.mayonTui;
          bilitui =
            assert lib.assertMsg (builtins.elem pkgs.bilitui.outPath (
              map (package: package.outPath) home.home.packages
            )) "Bilibili TUI must be installed by media";
            pkgs.bilitui;
          architecture = pkgs.runCommand "architecture-check" { } "touch $out";
          palette-contrast = paletteContrast;
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            statix check ${source}
            touch "$out"
          '';
          deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
            deadnix --fail --no-lambda-pattern-names ${source}
            touch "$out"
          '';
          protocols-composition = import ../tests/composition/protocols.nix { inherit inputs pkgs; };
          remote-workspace-composition = import ../tests/composition/remote.nix { inherit inputs pkgs; };
          embedded-composition = embedded.composition;
          embedded-home = embedded.home;
          local-services-composition = import ../tests/composition/local-services.nix {
            inherit inputs pkgs;
          };
          desktop-composition = import ../tests/composition/desktop.nix { inherit inputs pkgs; };
          editing-composition = import ../tests/composition/editing.nix { inherit inputs pkgs; };
          workspace-composition = import ../tests/composition/workspace.nix { inherit inputs pkgs; };
          system-boundaries = import ../tests/composition/system.nix {
            inherit inputs pkgs;
            host = nixos;
          };
        }
      );
    };
}
