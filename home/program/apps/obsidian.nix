{
  pkgs,
  lib,
  ...
}:
let
  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  mkObsidianCommunityPlugin =
    {
      name,
      owner,
      repo,
      version,
      hashes,
    }:
    let
      requiredFiles = [ "main.js" "manifest.json" ];
      optionalFiles = lib.filter (file: builtins.hasAttr file hashes) [ "styles.css" ];
      allFiles = requiredFiles ++ optionalFiles;

      fetchReleaseFile = file:
        pkgs.fetchurl {
          url = "https://github.com/${owner}/${repo}/releases/download/${version}/${file}";
          hash = hashes.${file};
        };
    in
    pkgs.runCommand "obsidian-plugin-${name}"
      { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        set -eu
        mkdir -p "$out"

        ${lib.concatMapStrings (file: ''
          cp "${fetchReleaseFile file}" "$out/${file}"
        '') allFiles}

        test -s "$out/main.js" || { echo "ERROR: main.js missing or empty"; exit 1; }
        test -s "$out/manifest.json" || { echo "ERROR: manifest.json missing or empty"; exit 1; }

        manifest_identity="$(jq -r '.id // .name // ""' "$out/manifest.json")"
        test -n "$manifest_identity" || {
          echo "ERROR: manifest.json must contain a non-empty id or name"
          exit 1
        }
      '';

  mkObsidianTheme =
    {
      name,
      owner,
      repo,
      rev,
      hash,
      author,
      version ? "0.0.0",
      minAppVersion ? "0.12.0",
    }:
    let
      src = pkgs.fetchFromGitHub {
        inherit owner repo rev hash;
      };

      manifest = pkgs.writeText "${name}-manifest.json" (builtins.toJSON {
        id = name;
        inherit name author version minAppVersion;
      });
    in
    pkgs.runCommand "obsidian-theme-${lib.strings.toLower name}" { } ''
      set -eu
      test -s "${src}/obsidian.css" || { echo "ERROR: obsidian.css missing or empty"; exit 1; }

      mkdir -p "$out"
      cp "${manifest}" "$out/manifest.json"
      cp "${src}/obsidian.css" "$out/theme.css"
    '';

  getDefinition =
    kind: defs: name:
    if builtins.hasAttr name defs then
      defs.${name}
    else
      throw "Unknown Obsidian ${kind} `${name}`. Available ${kind}s: ${lib.concatStringsSep ", " (builtins.attrNames defs)}";

  hasManifestIdentity =
    pkg:
    let
      manifest = builtins.fromJSON (builtins.readFile "${pkg}/manifest.json");
    in
    if manifest ? id && manifest.id != "" then
      true
    else if manifest ? name && manifest.name != "" then
      true
    else
      false;

  # ---------------------------------------------------------------------------
  # Available Themes
  # ---------------------------------------------------------------------------

  themeDefs = {
    atom = {
      pkg = mkObsidianTheme {
        name = "Atom";
        owner = "kognise";
        repo = "obsidian-atom";
        rev = "f067667e7c70b420b3031fe2424536c259198b99";
        hash = "sha256-4tNMID50GzUm1pWw/z+FTViJzKjjF09QVhnxel8kT0c=";
        author = "kognise";
      };
    };
  };

  # ---------------------------------------------------------------------------
  # Available Community Plugins
  # ---------------------------------------------------------------------------

  communityPluginDefs = {
    calendar = {
      pkg = mkObsidianCommunityPlugin {
        name = "calendar";
        owner = "liamcain";
        repo = "obsidian-calendar-plugin";
        version = "1.5.10";
        hashes = {
          "main.js" = "sha256-f7M56c+f2+WoAforirhbNmtbN3f70ZPLyHKLwncR0SU=";
          "manifest.json" = "sha256-8+lYEzhkhRK6oS1bRYSQ9/02eRj3vba9hhcc5Xvn0Is=";
        };
      };
      settings = { };
    };
    templater = {
      pkg = mkObsidianCommunityPlugin {
        name = "templater";
        owner = "SilentVoid13";
        repo = "Templater";
        version = "2.18.1";
        hashes = {
          "main.js" = "sha256-OQvgGm5beP+yG3nc4pZWTBJpcsMqTvlN7/gf4sQ+xcY=";
          "manifest.json" = "sha256-vvPoJiRlNa1FxpjzdePy2K3wgul+9DiWIuYOfD2laas=";
          "styles.css" = "sha256-99TuW9TsHQMu2h9OHaSB5xPFevlk7B5V0xSU8IYGjR4=";
        };
      };
      settings = { };
    };
    commander = {
      pkg = mkObsidianCommunityPlugin {
        name = "commander";
        owner = "phibr0";
        repo = "obsidian-commander";
        version = "0.5.4";
        hashes = {
          "main.js" = "sha256-+ja4qNogkhb+XbnCIAW2tDka3zCuUb3uswNQGA+1NTs=";
          "manifest.json" = "sha256-Xx9G6Y31hs2TbR+2gkNEh6nheqKoPrZ0nayj9D16kjY=";
          "styles.css" = "sha256-eiO1+U6HqV8hpEkZZGvCX/o9x9KpT+sMxoqcoh/Rcyk=";
        };
      };
      settings = { };
    };
    "easy-typing" = {
      pkg = mkObsidianCommunityPlugin {
        name = "easy-typing";
        owner = "Yaozhuwa";
        repo = "easy-typing-obsidian";
        version = "6.0.6";
        hashes = {
          "main.js" = "sha256-liRjUpGxq/PdDMXH0X5shltOK0P31unEqSn9G2OFTNc=";
          "manifest.json" = "sha256-4Vv8olN+faJBPN5Tti2aGoTNeMqUYSeDATS1ElAY/vo=";
          "styles.css" = "sha256-KpJQXHgoTFRWMo9dA105Qwkgekx0gu6tmWRt0qzlw30=";
        };
      };
      settings = { };
    };
    outliner = {
      pkg = mkObsidianCommunityPlugin {
        name = "outliner";
        owner = "vslinko";
        repo = "obsidian-outliner";
        version = "4.9.0";
        hashes = {
          "main.js" = "sha256-J4zXRLEgW956+l+SgfWohyS/HVdXN36OGaiwEgA2V24=";
          "manifest.json" = "sha256-rPgrp7ODYRXvyOA5RvoSNGYkq7Nvz4jeTh179K8ucoc=";
          "styles.css" = "sha256-eSKiZIg4lOafIsN/VJdE99RtHekm/IAqpOlMdc0vvOs=";
        };
      };
      settings = { };
    };
    "smart-connections" = {
      pkg = mkObsidianCommunityPlugin {
        name = "smart-connections";
        owner = "brianpetro";
        repo = "obsidian-smart-connections";
        version = "4.1.8";
        hashes = {
          "main.js" = "sha256-kf7na+hwkmUw5xNnl+WqOIjD6CbPcTbnldf4Pny29CA=";
          "manifest.json" = "sha256-grqvWMXNvLvVRnhd7HrrNCWW6/0zc59Na7ngS7sHJl4=";
          "styles.css" = "sha256-G+afasCSrObA/coLkiV/aOSqCNWv5ivYEV/kq1mW3sI=";
        };
      };
      settings = { };
    };
    "recent-files" = {
      pkg = mkObsidianCommunityPlugin {
        name = "recent-files";
        owner = "tgrosinger";
        repo = "recent-files-obsidian";
        version = "1.7.6";
        hashes = {
          "main.js" = "sha256-VCql9/RHuWfG9d9joR5D7dlriSZ5NW7ID/SqUEg2lis=";
          "manifest.json" = "sha256-cRo9NKyjqneiPBlLgDhqI8SLyZy/rfNHxs8/ExpPBgs=";
          "styles.css" = "sha256-LuSckqsLuEgiGglib3umdrvoU3LEyAZe53kLCDLLPds=";
        };
      };
      settings = { };
    };
    "file-explorer-note-count" = {
      pkg = mkObsidianCommunityPlugin {
        name = "file-explorer-note-count";
        owner = "ozntel";
        repo = "file-explorer-note-count";
        version = "1.2.4";
        hashes = {
          "main.js" = "sha256-/Ewzu1fcNef7Yjh4Nr7ELqAfQ/IrmsfOS+wcxOAOq9Q=";
          "manifest.json" = "sha256-tQ2km02kkO0CzFl10qxGSVaqLTmlaNzR+X4fwL7aNG0=";
          "styles.css" = "sha256-FznCtU9hqqSQL086Cb/36grqD4FF7qd6tBfELVXLgU4=";
        };
      };
      settings = { };
    };
    "better-word-count" = {
      pkg = mkObsidianCommunityPlugin {
        name = "better-word-count";
        owner = "lukeleppan";
        repo = "better-word-count";
        version = "0.10.1";
        hashes = {
          "main.js" = "sha256-zo6kp8S7FiIG5etbJ9lliDzksb7drh3kH766CEPFLck=";
          "manifest.json" = "sha256-RdahZC1+R+AcwytgJAXGUdkolxTKmg/RxeIutZeecxM=";
          "styles.css" = "sha256-8nnxmJ1OCZr4LwvHlb7vRe4waF6XRPZy3QyLUNZNTuE=";
        };
      };
      settings = { };
    };
    copilot = {
      pkg = mkObsidianCommunityPlugin {
        name = "copilot";
        owner = "logancyang";
        repo = "obsidian-copilot";
        version = "3.2.6";
        hashes = {
          "main.js" = "sha256-i2gaKSC1/Unlt27zpQ6c5LH8HwOdKXM7bBf89MbsjaQ=";
          "manifest.json" = "sha256-L8qt1g+T/C1tinfMkUwV6EkdEkA5otCIj8IvzwItbl0=";
          "styles.css" = "sha256-H/cyFCdmk4d70+GrZ9B5qnUYKmjElGO359vHW17AuVk=";
        };
      };
      settings = { };
    };
  };

  # ---------------------------------------------------------------------------
  # Enabled Names
  # ---------------------------------------------------------------------------

  enabledThemes = [ "atom" ];

  enabledCommunityPlugins = [
    "calendar"
    "templater"
    "commander"
    "easy-typing"
    "outliner"
    "smart-connections"
    "recent-files"
    "file-explorer-note-count"
    "better-word-count"
    "copilot"
  ];

  # ---------------------------------------------------------------------------
  # Resolved Entries
  # ---------------------------------------------------------------------------

  enabledThemeEntries = builtins.map (
    name:
    let
      theme = getDefinition "theme" themeDefs name;
    in
    {
      inherit (theme) pkg;
      enable = true;
    }
  ) enabledThemes;

  enabledCommunityPluginEntries = builtins.map (
    name:
    let
      plugin = getDefinition "community plugin" communityPluginDefs name;
    in
    {
      inherit (plugin) pkg;
      enable = true;
      settings = plugin.settings or { };
    }
  ) enabledCommunityPlugins;
in
{
  assertions = [
    {
      assertion = builtins.all (name: builtins.hasAttr name themeDefs) enabledThemes;
      message = "Every enabled Obsidian theme must exist in themeDefs.";
    }
    {
      assertion = builtins.length enabledThemes <= 1;
      message = "Only one Obsidian theme can be enabled at a time.";
    }
    {
      assertion = builtins.all (name: builtins.hasAttr name communityPluginDefs) enabledCommunityPlugins;
      message = "Every enabled Obsidian community plugin must exist in communityPluginDefs.";
    }
    {
      assertion = builtins.all (
        theme:
        builtins.pathExists "${theme.pkg}/manifest.json"
        && builtins.pathExists "${theme.pkg}/theme.css"
        && hasManifestIdentity theme.pkg
      ) enabledThemeEntries;
      message = "Every enabled Obsidian theme must provide theme.css and a manifest with a non-empty id or name.";
    }
    {
      assertion = builtins.all (
        plugin:
        builtins.pathExists "${plugin.pkg}/main.js"
        && builtins.pathExists "${plugin.pkg}/manifest.json"
        && hasManifestIdentity plugin.pkg
      ) enabledCommunityPluginEntries;
      message = "Every enabled Obsidian community plugin must provide main.js, manifest.json, and a manifest with a non-empty id or name.";
    }
  ];

  programs.obsidian = {
    enable = true;
    package = pkgs.obsidian;

    vaults.main = {
      enable = true;
      target = "Notes";
      settings = {
        themes = enabledThemeEntries;
        communityPlugins = enabledCommunityPluginEntries;
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
