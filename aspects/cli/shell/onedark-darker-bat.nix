{
  pkgs,
  palette,
}:
let
  mix =
    base: tint: percent:
    import ./color-mix.nix { inherit base tint percent; };
  diff = {
    add = mix palette.deep palette.green 8;
    addEmph = mix palette.deep palette.green 12;
    delete = mix palette.deep palette.red 8;
    deleteEmph = mix palette.deep palette.red 12;
    change = mix palette.deep palette.blue 8;
    changeEmph = mix palette.deep palette.blue 12;
  };
  entries = [
    {
      name = "Foreground";
      scope = "text, source, punctuation, meta.tag punctuation.definition.tag";
      foreground = palette.brightFg;
    }
    {
      name = "Comment";
      scope = "comment, punctuation.definition.comment";
      foreground = palette.fg;
      fontStyle = "italic";
    }
    {
      name = "Keyword";
      scope = "keyword, storage, storage.type, storage.modifier, entity.name.tag.yaml";
      foreground = palette.cyan;
    }
    {
      name = "String";
      scope = "string, string.quoted, string.template";
      foreground = palette.green;
    }
    {
      name = "String escape";
      scope = "constant.character.escape, string constant.character";
      foreground = palette.cyan;
    }
    {
      name = "Number";
      scope = "constant.numeric, constant.language";
      foreground = palette.orange;
    }
    {
      name = "Function";
      scope = "entity.name.function, support.function";
      foreground = palette.blue;
    }
    {
      name = "Type";
      scope = "entity.name.type, entity.name.class, support.type, support.class";
      foreground = palette.yellow;
    }
    {
      name = "Variable";
      scope = "variable, variable.other, meta.definition.variable";
      foreground = palette.brightFg;
    }
    {
      name = "Constant";
      scope = "constant, variable.other.constant";
      foreground = palette.orange;
    }
    {
      name = "Operator";
      scope = "keyword.operator, punctuation.separator, punctuation.accessor";
      foreground = palette.cyan;
    }
    {
      name = "Tag";
      scope = "entity.name.tag, punctuation.definition.tag";
      foreground = palette.brightFg;
    }
    {
      name = "Attribute";
      scope = "entity.other.attribute-name";
      foreground = palette.blue;
    }
    {
      name = "Heading";
      scope = "markup.heading, entity.name.section";
      foreground = palette.blue;
      fontStyle = "bold";
    }
    {
      name = "Markup emphasis";
      scope = "markup.bold";
      foreground = palette.yellow;
      fontStyle = "bold";
    }
    {
      name = "Markup italic";
      scope = "markup.italic";
      fontStyle = "italic";
    }
    {
      name = "Markup link";
      scope = "markup.underline.link, string.other.link";
      foreground = palette.cyan;
      fontStyle = "underline";
    }
    {
      name = "Diff inserted";
      scope = "markup.inserted, meta.diff.header.to-file";
      foreground = palette.brightFg;
      background = diff.add;
    }
    {
      name = "Diff deleted";
      scope = "markup.deleted, meta.diff.header.from-file";
      foreground = palette.brightFg;
      background = diff.delete;
    }
    {
      name = "Diff modified";
      scope = "markup.changed";
      foreground = palette.brightFg;
      background = diff.change;
    }
    {
      name = "Invalid";
      scope = "invalid, invalid.illegal";
      foreground = palette.brightFg;
      fontStyle = "underline";
    }
  ];

  plistString = value: "<string>${value}</string>";
  plistDict = attributes: ''
    <dict>
      ${builtins.concatStringsSep "\n" (
        builtins.attrValues (
          builtins.mapAttrs (key: value: "<key>${key}</key>${plistString value}") attributes
        )
      )}
    </dict>
  '';
  rule = entry: ''
    <dict>
      <key>name</key>${plistString entry.name}
      <key>scope</key>${plistString entry.scope}
      <key>settings</key>
      ${plistDict (
        (if entry ? foreground then { inherit (entry) foreground; } else { })
        // (if entry ? fontStyle then { inherit (entry) fontStyle; } else { })
        // (if entry ? background then { inherit (entry) background; } else { })
      )}
    </dict>
  '';
  tmTheme = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>${plistString "One Dark Darker"}
      <key>settings</key>
      <array>
        <dict><key>settings</key>${
          plistDict {
            foreground = palette.brightFg;
            background = palette.deep;
            caret = palette.blue;
            inherit (palette) selection;
            lineHighlight = palette.selection;
          }
        }</dict>
        ${builtins.concatStringsSep "\n" (map rule entries)}
      </array>
    </dict>
    </plist>
  '';
  themeSource = pkgs.runCommand "onedark-darker-bat-theme-source" { } ''
    mkdir -p "$out/themes"
    cp ${pkgs.writeText "One Dark Darker.tmTheme" tmTheme} "$out/themes/One Dark Darker.tmTheme"
  '';
  cache = pkgs.runCommand "onedark-darker-bat-cache" { nativeBuildInputs = [ pkgs.bat ]; } ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME"
    cd ${pkgs.emptyDirectory}
    ${pkgs.bat}/bin/bat cache --build --source ${themeSource} --target "$out"
  '';
  deltaCacheRoot = pkgs.runCommand "onedark-darker-delta-cache-root" { } ''
    mkdir -p "$out"
    ln -s ${cache} "$out/bat"
  '';
  delta = pkgs.symlinkJoin {
    name = "delta-onedark-darker";
    paths = [ pkgs.delta ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/delta" --set XDG_CACHE_HOME ${deltaCacheRoot}
    '';
    inherit (pkgs.delta) meta;
  };
in
{
  name = "One Dark Darker";
  inherit
    tmTheme
    cache
    delta
    diff
    ;
}
