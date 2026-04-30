{ pkgs, lib }:
{
  mkObsidianCommunityPlugin =
    {
      name,
      owner,
      repo,
      version,
      hashes,
    }:
    let
      requiredFiles = [
        "main.js"
        "manifest.json"
      ];
      optionalFiles = lib.filter (file: builtins.hasAttr file hashes) [ "styles.css" ];
      allFiles = requiredFiles ++ optionalFiles;

      fetchReleaseFile =
        file:
        pkgs.fetchurl {
          url = "https://github.com/${owner}/${repo}/releases/download/${version}/${file}";
          hash = hashes.${file};
        };
    in
    pkgs.runCommand "obsidian-plugin-${name}" { nativeBuildInputs = [ pkgs.jq ]; } ''
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
        inherit
          owner
          repo
          rev
          hash
          ;
      };

      manifest = pkgs.writeText "${name}-manifest.json" (
        builtins.toJSON {
          id = name;
          inherit
            name
            author
            version
            minAppVersion
            ;
        }
      );
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
}
