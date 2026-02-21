{
    pkgs,
    ...
}:

let
    atomThemeRev = "f067667e7c70b420b3031fe2424536c259198b99";
    atomThemeSrc = pkgs.fetchFromGitHub {
        owner = "kognise";
        repo = "obsidian-atom";
        rev = atomThemeRev;
        hash = "sha256-4tNMID50GzUm1pWw/z+FTViJzKjjF09QVhnxel8kT0c=";
    };

    atomThemeManifest = pkgs.writeText "atom-theme-manifest.json" (builtins.toJSON {
        id = "Atom";
        name = "Atom";
        author = "kognise";
        version = "0.0.0";
        minAppVersion = "0.12.0";
    });

    atomThemePkg = pkgs.runCommand "obsidian-theme-atom" { } ''
        set -eu
        test -f "${atomThemeSrc}/obsidian.css"
        mkdir -p "$out"
        cp "${atomThemeManifest}" "$out/manifest.json"
        cp "${atomThemeSrc}/obsidian.css" "$out/theme.css"
    '';

    latexsuitVersion = "1.10.4";
    latexsuitMainJs = pkgs.fetchurl {
        url = "https://github.com/artisticat1/obsidian-latex-suite/releases/download/${latexsuitVersion}/main.js";
        hash = "sha256-GbNJZK2Dd/nQ/NUO6Sbpz7Uz0sKTotM5NJP76zF+AWE=";
    };
    latexsuitManifest = pkgs.fetchurl {
        url = "https://github.com/artisticat1/obsidian-latex-suite/releases/download/${latexsuitVersion}/manifest.json";
        hash = "sha256-0eObNbFP6BkjWhV+29vmt2sMmqP/iIPpzONj9Qy5WPk=";
    };
    latexsuitStyles = pkgs.fetchurl {
        url = "https://github.com/artisticat1/obsidian-latex-suite/releases/download/${latexsuitVersion}/styles.css";
        hash = "sha256-quy5F0fDXV0+b88bocEa293LA3PDvZKoCZsKpO5IkMQ=";
    };

    latexsuitPluginPkg = pkgs.runCommand "obsidian-plugin-latexsuite" { } ''
        set -eu
        test -f "${latexsuitManifest}"
        test -f "${latexsuitMainJs}"

        manifest_id="$(${pkgs.gnused}/bin/sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' "${latexsuitManifest}" | ${pkgs.coreutils}/bin/head -n1)"
        test -n "$manifest_id"

        mkdir -p "$out"
        cp "${latexsuitManifest}" "$out/manifest.json"
        cp "${latexsuitMainJs}" "$out/main.js"
        cp "${latexsuitStyles}" "$out/styles.css"
    '';
in
{
    assertions = [
        {
            assertion = atomThemeRev != "";
            message = "Obsidian Atom theme revision must be pinned and non-empty.";
        }
        {
            assertion = latexsuitVersion != "";
            message = "Obsidian latexsuit plugin version must be pinned and non-empty.";
        }
    ];

    programs.obsidian = {
        enable = true;
        package = pkgs.obsidian;
        vaults = {
            main = {
                enable = true;
                target = "Notes";
                settings = {
                    themes = [
                        {
                            pkg = atomThemePkg;
                            enable = true;
                        }
                    ];
                    communityPlugins = [
                        {
                            pkg = latexsuitPluginPkg;
                            enable = true;
                            settings = { };
                        }
                    ];
                };
            };
        };
        defaultSettings = {
            app = {
                alwaysUpdateLinks = true;
                showInlineTitle = true;
                spellcheck = true;
            };
            appearance = {
                baseTheme = "obsidian";
            };
            corePlugins = [
                "backlink"
                "command-palette"
                "daily-notes"
                "file-explorer"
                "file-recovery"
                "global-search"
                "outline"
                "switcher"
                "tag-pane"
                "templates"
            ];
        };
    };
}
