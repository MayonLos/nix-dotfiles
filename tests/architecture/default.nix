{
  lib,
  root,
  unstableNames ? [ ],
  unstableInspectors ? [ ],
  publicFiles ? [ ],
  reservedNames ? [
    "nixos-btw"
    "mayon"
    "mayon@nixos-btw"
  ],
  evaluatedAspectIds ? null,
  sources ? null,
  includeFixtures ? true,
  returnErrors ? false,
}:
let
  inherit (builtins)
    attrNames
    elem
    filter
    match
    readDir
    readFile
    ;
  hasSuffix =
    suffix: value:
    let
      n = builtins.stringLength value;
      m = builtins.stringLength suffix;
    in
    n >= m && builtins.substring (n - m) m value == suffix;
  hasAnySuffix = suffixes: value: builtins.any (suffix: hasSuffix suffix value) suffixes;
  split = value: filter (part: part != "") (lib.splitString "/" value);
  join = builtins.concatStringsSep "/";
  normalize =
    value:
    let
      step =
        acc: part:
        if part == "." then
          acc
        else if part == ".." then
          builtins.genList (i: builtins.elemAt acc i) (if acc == [ ] then 0 else builtins.length acc - 1)
        else
          acc ++ [ part ];
    in
    join (builtins.foldl' step [ ] (split value));

  # Parse one line at a time so a large source file does not consume one Nix call
  # frame per character. Carry only block-comment/string state between lines.
  stripComments =
    text:
    let
      scanLine =
        initial: line:
        let
          len = builtins.stringLength line;
          at = i: if i < len then builtins.substring i 1 line else "";
          go =
            i: depth: inString: escaped: out:
            if i >= len then
              {
                text = lib.concatStrings (lib.reverseList out);
                inherit depth inString escaped;
              }
            else
              let
                c = at i;
                next = at (i + 1);
              in
              if depth > 0 then
                if c == "/" && next == "*" then
                  go (i + 2) (depth + 1) inString false ([ " " ] ++ out)
                else if c == "*" && next == "/" then
                  go (i + 2) (depth - 1) inString false out
                else
                  go (i + 1) depth inString false out
              else if inString then
                if escaped then
                  go (i + 1) 0 true false ([ c ] ++ out)
                else if c == "\\" then
                  go (i + 1) 0 true true ([ c ] ++ out)
                else if c == "\"" then
                  go (i + 1) 0 false false ([ c ] ++ out)
                else
                  go (i + 1) 0 true false ([ c ] ++ out)
              else if c == "/" && next == "*" then
                go (i + 2) 1 false false ([ " " ] ++ out)
              else if c == "#" then
                {
                  text = lib.concatStrings (lib.reverseList out);
                  depth = 0;
                  inString = false;
                  escaped = false;
                }
              else if c == "\"" then
                go (i + 1) 0 true false ([ c ] ++ out)
              else
                go (i + 1) 0 false false ([ c ] ++ out);
        in
        go 0 initial.depth initial.inString initial.escaped [ ];
      initial = {
        depth = 0;
        inString = false;
        escaped = false;
        lines = [ ];
      };
      final = lib.foldl' (
        state: line:
        let
          scanned = scanLine state line;
        in
        {
          inherit (scanned) depth inString escaped;
          lines = [ scanned.text ] ++ state.lines;
        }
      ) initial (lib.splitString "\n" text);
    in
    lib.concatStringsSep "\n" (lib.reverseList final.lines);

  readTree =
    dir: prefix:
    let
      entries = readDir dir;
    in
    lib.concatMap (
      name:
      let
        kind = entries.${name};
        rel = if prefix == "" then name else "${prefix}/${name}";
        full = dir + "/${name}";
      in
      if
        lib.hasPrefix "." name
        || lib.hasPrefix "result" name
        || rel == "tests/architecture"
        || lib.hasPrefix "tests/architecture/" rel
      then
        [ ]
      else if kind == "directory" then
        readTree full rel
      else if kind == "regular" then
        [
          {
            path = rel;
            text = if hasSuffix ".nix" name || hasSuffix ".md" name then readFile full else "";
          }
        ]
      else
        [ ]
    ) (attrNames entries);
  allSources =
    if sources == null then
      readTree root ""
    else
      map (path: {
        inherit path;
        text = sources.${path};
      }) (attrNames sources);
  codeSources = filter (source: hasSuffix ".nix" source.path) allSources;
  sourceNames = map (source: source.path) allSources;
  # Palette regression checking covers source/config/document text formats
  # beyond Nix and Markdown. Known generated/binary formats are skipped before
  # readFile so large assets and invalid UTF-8 never enter the evaluator.
  binarySuffixes = [
    ".png"
    ".jpg"
    ".jpeg"
    ".webp"
    ".gif"
    ".ico"
    ".icns"
    ".bmp"
    ".tif"
    ".tiff"
    ".avif"
    ".heic"
    ".pdf"
    ".woff"
    ".woff2"
    ".ttf"
    ".otf"
    ".eot"
    ".mp3"
    ".ogg"
    ".wav"
    ".flac"
    ".m4a"
    ".mp4"
    ".mkv"
    ".webm"
    ".mov"
    ".avi"
    ".zip"
    ".gz"
    ".xz"
    ".bz2"
    ".zst"
    ".7z"
    ".rar"
    ".tar"
    ".sqlite"
    ".db"
    ".bin"
    ".so"
    ".a"
    ".o"
    ".class"
    ".jar"
    ".wasm"
    ".lockb"
    ".pyc"
    ".DS_Store"
  ];
  paletteTextSources =
    if sources != null then
      map (path: {
        inherit path;
        text = sources.${path};
      }) (attrNames sources)
    else
      lib.concatMap (source: if source.text != "" then [ source ] else [ ]) allSources
      ++ (
        let
          readTextTree =
            dir: prefix:
            lib.concatMap (
              name:
              let
                kind = (readDir dir).${name};
                rel = if prefix == "" then name else "${prefix}/${name}";
                full = dir + "/${name}";
              in
              if
                (
                  kind == "directory"
                  && builtins.elem name [
                    ".git"
                    ".work"
                    ".team"
                    ".worktrees"
                  ]
                )
                || lib.hasPrefix "result" name
                || rel == "docs/history"
                || lib.hasPrefix "docs/history/" rel
              then
                [ ]
              else if kind == "directory" then
                readTextTree full rel
              else if
                kind == "regular"
                && !(hasAnySuffix binarySuffixes name)
                && (!(hasSuffix ".nix" name || hasSuffix ".md" name) || !(elem rel sourceNames))
                && name != "ONEDARK-LICENSE"
              then
                [
                  {
                    path = rel;
                    text = readFile full;
                  }
                ]
              else
                [ ]
            ) (attrNames (readDir dir));
        in
        readTextTree root ""
      );
  forbiddenPaletteHexes = map (value: "#" + value) [
    "1f2329"
    "4fa6ed"
    "bf68d9"
    "282c34"
    "a0a8b7"
    "535965"
    "8ebd6b"
    "cc9057"
    "e2b86b"
    "48b0bd"
    "e55561"
    "d1d5de"
    "7a818e"
    "30363f"
  ];
  paletteColorAllowed =
    source: !(source.path == "ONEDARK-LICENSE" || lib.hasPrefix "docs/history/" source.path);
  paletteErrors = lib.concatMap (
    source:
    if !paletteColorAllowed source then
      [ ]
    else
      lib.concatMap (
        color:
        if lib.hasInfix color (lib.toLower source.text) then
          [ (error "legacy-palette-color" source.path "contains removed palette color ${color}") ]
        else
          [ ]
      ) forbiddenPaletteHexes
  ) paletteTextSources;
  sourceMap = builtins.listToAttrs (
    map (source: {
      name = source.path;
      value = source.text;
    }) allSources
  );
  code = path: stripComments (sourceMap.${path} or "");
  hasMatch = regex: text: builtins.any (line: match regex line != null) (lib.splitString "\n" text);

  pathRefs =
    text:
    let
      ordinary = map builtins.head (
        filter builtins.isList (builtins.split "(\\.\\./[A-Za-z0-9_./@+-]+|\\./[A-Za-z0-9_./@+-]+)" text)
      );
      interpolated = filter builtins.isList (
        builtins.split "\\$[{][[:space:]]*(\\.\\./[A-Za-z0-9_./@+-]+|\\./[A-Za-z0-9_./@+-]+)[[:space:]]*[}](/[A-Za-z0-9_./@+-]+)" text
      );
      joined = map (parts: (builtins.elemAt parts 0) + (builtins.elemAt parts 1)) interpolated;
    in
    lib.unique (ordinary ++ joined);
  dirname =
    path:
    join (builtins.genList (i: builtins.elemAt (split path) i) (builtins.length (split path) - 1));
  resolve = sourcePath: token: normalize "${dirname sourcePath}/${token}";
  featureOf =
    path:
    let
      parts = split path;
    in
    if builtins.length parts >= 3 && builtins.elemAt parts 0 == "aspects" then
      "aspects/${builtins.elemAt parts 1}/${builtins.elemAt parts 2}"
    else
      null;
  # A feature is a real two-level directory under aspects/, whether or not it
  # has an entrypoint yet. Deriving from all source files lets us diagnose an
  # unregistered directory that currently contains only private resources.
  featureDirs = lib.unique (filter (path: path != null) (map featureOf sourceNames));
  registry = "aspects/default.nix";
  registered = lib.unique (
    filter (path: featureOf path != null) (
      map (token: resolve registry token) (pathRefs (code registry))
    )
  );
  publicTarget =
    path:
    elem path featureDirs
    || elem path (map (dir: "${dir}/default.nix") featureDirs)
    || elem path (map (dir: "${dir}/contract.nix") featureDirs)
    || builtins.any (public: path == public || lib.hasPrefix "${public}/" path) publicFiles;
  error =
    rule: path: message:
    "${rule}: ${path}: ${message}";

  referenceErrors = lib.concatMap (
    source:
    let
      from = featureOf source.path;
    in
    lib.concatMap (
      token:
      let
        target = resolve source.path token;
        to = featureOf target;
        privateCrossing = to != null && (from == null || to != from) && !(publicTarget target);
      in
      if privateCrossing then
        [ (error "private-reference" source.path "${token} resolves to private ${target}") ]
      else
        [ ]
    ) (pathRefs (stripComments source.text))
  ) codeSources;

  inventoryErrors = lib.concatMap (
    source:
    if !(lib.hasPrefix "inventory/" source.path) then
      [ ]
    else
      let
        text = code source.path;
        banned = [
          "pkgs"
          "runCommand"
          "writeText"
          "writeShellScript"
          "writeShellScriptBin"
          "writeShellApplication"
          "toFile"
          "activation"
          "script"
        ];
        words = lib.concatMap (
          word:
          if hasMatch ".*([^A-Za-z0-9_-]|^)${word}([^A-Za-z0-9_-]|$).*" text then
            [ (error "inventory-implementation" source.path "contains ${word}") ]
          else
            [ ]
        ) banned;
        isHardware = hasSuffix "/hardware-configuration.nix" source.path;
        isSecrets = hasSuffix "/secrets.nix" source.path;
        isRegistration = hasSuffix "/default.nix" source.path;
        hasImports = hasMatch ".*imports[[:space:]]*=.*" text;
        importBlocks = filter builtins.isList (
          builtins.split "imports[[:space:]]*=[[:space:]]*\\[([^;]*)];" text
        );
        relativeImports = map (token: resolve source.path token) (
          lib.concatMap (block: pathRefs (builtins.head block)) importBlocks
        );
        allowedInventoryImport =
          path:
          lib.hasPrefix "inventory/users/" path
          || match ".*/users/[^/]+\\.nix" path != null
          || hasSuffix "/facts.nix" path
          || hasSuffix "/hardware-configuration.nix" path
          || hasSuffix "/secrets.nix" path
          || elem "${path}/default.nix" sourceNames;
        hasExternalModule = hasMatch ".*inputs\\.[A-Za-z0-9_-]+\\.nixosModules\\..*" text;
        localRegistration =
          isRegistration
          && builtins.all allowedInventoryImport relativeImports
          && (!hasExternalModule || hasMatch ".*sops.*" text);
        sopsDeclaration = isSecrets && hasMatch ".*sops.*" text && relativeImports == [ ];
        imports =
          if hasImports && !(isHardware || localRegistration || sopsDeclaration) then
            [
              (error "inventory-import" source.path
                "imports are reserved for inventory registration, hardware-configuration, and sops declarations"
              )
            ]
          else
            [ ];
      in
      words ++ imports
  ) codeSources;

  findCaptures =
    regex: text:
    lib.unique (
      map builtins.head (
        filter builtins.isList (lib.concatMap (line: builtins.split regex line) (lib.splitString "\n" text))
      )
    );
  legacyErrors = lib.concatMap (
    source:
    let
      hit = findCaptures "(pkgs-unstable)" (code source.path) != [ ];
      exempt = source.path == "flake.nix" || source.path == "nix/pkgs.nix";
    in
    if hit && !exempt then
      [ (error "legacy-unstable-arg" source.path "pkgs-unstable is a removed module argument") ]
    else
      [ ]
  ) codeSources;
  unstableErrors = lib.concatMap (
    source:
    let
      text = code source.path;
      selectedNames = findCaptures "pkgs\\.unstable\\.([A-Za-z_][A-Za-z0-9_-]*)" text;
      names = filter (name: !(elem name unstableNames)) selectedNames;
      # Only an explicit literal selection is auditable. This also catches
      # inherit (pkgs.unstable), `with pkgs.unstable`, and aliases that would
      # otherwise bypass the name whitelist.
      withoutSelections = builtins.replaceStrings (map (name: "pkgs.unstable.${name}") selectedNames) (map
        (_: "")
        selectedNames
      ) text;
      nonDot = hasMatch ".*pkgs\\.unstable([^A-Za-z0-9_-]|$).*" withoutSelections;
      dynamic = builtins.any (line: match ".*pkgs\\.unstable\\.\\$\\{.*" line != null) (
        lib.splitString "\n" text
      );
    in
    map (
      name: error "unstable-not-whitelisted" source.path "pkgs.unstable.${name} is not in unstableNames"
    ) names
    ++ (
      if dynamic then
        [
          (error "unstable-dynamic-access" source.path
            "dynamic pkgs.unstable attribute cannot be checked against the whitelist"
          )
        ]
      else
        [ ]
    )
    ++ (
      if nonDot && !(elem source.path unstableInspectors) then
        [
          (error "unstable-nondot-access" source.path
            "pkgs.unstable must be followed by an explicit literal attribute selection"
          )
        ]
      else
        [ ]
    )
  ) codeSources;

  hasForceDirective =
    line:
    let
      n = builtins.stringLength line;
      go =
        i: inString: escaped: inBlock:
        if i >= n then
          false
        else
          let
            c = builtins.substring i 1 line;
            next = if i + 1 < n then builtins.substring (i + 1) 1 line else "";
            rest = builtins.substring i (n - i) line;
          in
          if inBlock then
            if c == "*" && next == "/" then go (i + 2) false false false else go (i + 1) false false true
          else if inString then
            if escaped then
              go (i + 1) true false false
            else if c == "\\" then
              go (i + 1) true true false
            else if c == "\"" then
              go (i + 1) false false false
            else
              go (i + 1) true false false
          else if c == "/" && next == "*" then
            go (i + 2) false false true
          else if c == "\"" then
            go (i + 1) true false false
          else if c == "#" then
            match "^#[[:space:]]*force:[[:space:]]*[^[:space:]].*" rest != null
          else
            go (i + 1) false false false;
    in
    go 0 false false false;
  forceErrors = lib.concatMap (
    source:
    let
      raw = lib.splitString "\n" source.text;
      lines = lib.splitString "\n" (code source.path);
    in
    lib.concatLists (
      lib.imap0 (
        i: line:
        let
          previous = if i == 0 then "" else builtins.elemAt raw (i - 1);
          current = builtins.elemAt raw i;
          usesForce = match ".*mk(Force|Override).*" line != null;
          reason = hasForceDirective current || hasForceDirective previous;
        in
        if usesForce && !reason then
          [
            (error "force-reason" source.path
              "line ${toString (i + 1)} uses mkForce/mkOverride without adjacent # force: reason"
            )
          ]
        else
          [ ]
      ) lines
    )
  ) codeSources;

  literalAspectIds = lib.concatMap (
    dir:
    let
      path = "${dir}/default.nix";
    in
    findCaptures "den\\.aspects\\.([A-Za-z_][A-Za-z0-9_-]*)(\\.(homeManager|nixos|user))?[[:space:]]*=" (
      code path
    )
  ) featureDirs;
  literalAspectOwners = lib.concatMap (
    dir:
    map
      (id: {
        inherit id;
        owner = dir;
      })
      (
        findCaptures "den\\.aspects\\.([A-Za-z_][A-Za-z0-9_-]*)(\\.(homeManager|nixos|user))?[[:space:]]*=" (
          code "${dir}/default.nix"
        )
      )
  ) featureDirs;
  flattened = text: builtins.replaceStrings [ "\n" "\r" "\t" ] [ " " " " " " ] text;
  attrsetAspectIds = lib.concatMap (
    id:
    if
      builtins.any (
        dir:
        let
          text = flattened (code "${dir}/default.nix");
        in
        match ".*den\\.aspects[[:space:]]*=[[:space:]]*\\{.*([^A-Za-z0-9_-]|^)${id}[[:space:]]*=.*" text
        != null
      ) featureDirs
    then
      [ id ]
    else
      [ ]
  ) reservedNames;
  staticAspectIds = lib.unique (literalAspectIds ++ attrsetAspectIds);
  aspectIds = if evaluatedAspectIds == null then staticAspectIds else evaluatedAspectIds;
  reservedErrors = map (
    id:
    error "reserved-aspect-name" "aspects/"
      "functional aspect ID ${id} collides with an inventory entity"
  ) (filter (id: elem id reservedNames) aspectIds);
  duplicateIds = lib.unique (
    map (record: record.id) (
      filter (
        record:
        builtins.any (other: other.id == record.id && other.owner != record.owner) literalAspectOwners
      ) literalAspectOwners
    )
  );
  registryErrors =
    map (
      dir:
      error "unregistered-feature" "${dir}/default.nix"
        "feature directory is absent from aspects/default.nix imports"
    ) (filter (dir: !(elem dir registered)) featureDirs)
    ++ map (
      dir: error "missing-feature-directory" registry "registered feature ${dir} has no default.nix"
    ) (filter (dir: !(elem dir featureDirs)) registered)
    ++ map (dir: error "missing-feature-entry" dir "feature directory has no default.nix entrypoint") (
      filter (dir: !(elem "${dir}/default.nix" sourceNames)) featureDirs
    )
    ++ reservedErrors
    ++ map (
      id: error "duplicate-aspect-name" "aspects/" "aspect ID ${id} is declared more than once"
    ) duplicateIds;

  readmeErrors = lib.concatMap (
    dir:
    let
      files = filter (path: lib.hasPrefix "${dir}/" path) sourceNames;
      defaultCode = code "${dir}/default.nix";
      classContents = hasMatch ".*(homeManager|nixos|user)[[:space:]]*=.*" defaultCode;
      ownedFiles = filter (
        path:
        !(elem path [
          "${dir}/default.nix"
          "${dir}/README.md"
          "${dir}/checks.nix"
          "${dir}/contract.nix"
        ])
      ) files;
      required =
        elem "${dir}/contract.nix" files
        || elem "${dir}/nixos.nix" files
        || elem "${dir}/home.nix" files
        || elem "${dir}/user.nix" files
        || classContents
        || ownedFiles != [ ];
    in
    if required && !(elem "${dir}/README.md" sourceNames) then
      [
        (error "missing-feature-readme" dir
          "feature has a contract, class content, or owned resources/configuration"
        )
      ]
    else
      [ ]
  ) featureDirs;

  libFiles = filter (path: lib.hasPrefix "lib/" path && hasSuffix ".nix" path) sourceNames;
  libErrors = lib.concatMap (
    path:
    let
      consumers = lib.concatMap (
        source:
        if lib.hasPrefix "lib/" source.path then
          [ ]
        else if
          elem path (map (token: resolve source.path token) (pathRefs (stripComments source.text)))
        then
          [ source.path ]
        else
          [ ]
      ) codeSources;
    in
    if consumers == [ ] then
      [ (error "unused-lib" path "no non-lib source imports this helper") ]
    else
      [ ]
  ) libFiles;

  errors =
    paletteErrors
    ++ referenceErrors
    ++ inventoryErrors
    ++ legacyErrors
    ++ unstableErrors
    ++ forceErrors
    ++ registryErrors
    ++ readmeErrors
    ++ libErrors;
  fixture =
    name: fixtureSources: opts: expected:
    let
      args = {
        inherit lib root;
        sources = fixtureSources;
        includeFixtures = false;
        returnErrors = true;
      }
      // opts;
      found = import ./default.nix args;
      result = builtins.tryEval (
        builtins.deepSeq (import ./default.nix (args // { returnErrors = false; })) true
      );
      classified = builtins.any (message: lib.hasInfix expected message) found;
    in
    if classified && !result.success then
      [ ]
    else
      [
        "architecture-fixture: ${name}: expected diagnostic ${expected} and a thrown import; errors=${builtins.toJSON found}, threw=${toString (!result.success)}"
      ];
  fixtureAbsent =
    name: fixtureSources: opts: unexpected:
    let
      args = {
        inherit lib root;
        sources = fixtureSources;
        includeFixtures = false;
        returnErrors = true;
      }
      // opts;
      found = import ./default.nix args;
      result = builtins.tryEval (
        builtins.deepSeq (import ./default.nix (args // { returnErrors = false; })) true
      );
    in
    if builtins.any (message: lib.hasInfix unexpected message) found then
      [ "architecture-fixture: ${name}: unexpected ${unexpected}; got ${builtins.toJSON found}" ]
    else if !result.success then
      [
        "architecture-fixture: ${name}: legal fixture unexpectedly throws; errors=${builtins.toJSON found}"
      ]
    else
      [ ];
  fixtures = [
    (fixture "legacy palette color in non-Nix text" {
      "aspects/desktop/example/theme.css" =
        ".old { color: "
        + (lib.concatStrings [
          "#"
          "1f2329"
        ])
        + "; }";
    } { } "legacy-palette-color")
    (fixtureAbsent "legacy palette color in excluded history" {
      "docs/history/old.md" =
        "Historical palette used "
        + (lib.concatStrings [
          "#"
          "1f2329"
        ])
        + ".";
    } { } "legacy-palette-color")
    (fixture "private ordinary path" {
      "aspects/cli/shell/default.nix" = "x = import ../../desktop/greeter/private.nix;";
      "aspects/desktop/greeter/default.nix" = "den.aspects.greeter = {};";
    } { } "private-reference")
    (fixture "private interpolation path" {
      "aspects/cli/shell/default.nix" = ''x = import "''${ ../../desktop/greeter/private.nix }";'';
      "aspects/desktop/greeter/default.nix" = "den.aspects.greeter = {};";
    } { } "private-reference")
    (fixture "private path concatenated after interpolation" {
      "aspects/cli/shell/default.nix" = ''x = import "''${ ../../desktop/greeter }/private.nix";'';
      "aspects/desktop/greeter/default.nix" = "den.aspects.greeter = {};";
    } { } "private-reference")
    (fixture "non-feature private path" {
      "tests/sample.nix" = "x = import ../aspects/desktop/greeter/private.nix;";
      "aspects/desktop/greeter/default.nix" = "den.aspects.greeter = {};";
    } { } "private-reference")
    (fixture "inventory implementation" {
      "inventory/hosts/demo/default.nix" = "x = pkgs.writeText \"a\" \"b\";";
    } { } "inventory-implementation")
    (fixture "inventory imports" {
      "inventory/users/demo.nix" = "{ imports = [ ./implementation.nix ]; }";
    } { } "inventory-import")
    (fixture "legacy unstable argument" {
      "aspects/cli/shell/default.nix" = "{ pkgs-unstable, ... }: {};";
    } { } "legacy-unstable-arg")
    (fixture "unstable whitelist" { "aspects/cli/shell/default.nix" = "pkgs.unstable.secretPkg"; } {
      unstableNames = [ "allowed" ];
    } "unstable-not-whitelisted")
    (fixture "unstable inherit bypass" {
      "aspects/cli/shell/default.nix" = "{ inherit (pkgs.unstable) notAllowed; }";
    } { unstableNames = [ "notAllowed" ]; } "unstable-nondot-access")
    (fixtureAbsent "whitelisted literal unstable selection" {
      "aspects/default.nix" = "imports = [ ./cli/shell ];";
      "aspects/cli/shell/default.nix" = "pkgs.unstable.allowed";
    } { unstableNames = [ "allowed" ]; } "unstable-nondot-access")
    (fixture "dynamic unstable access" {
      "aspects/cli/shell/default.nix" = "pkgs.unstable.\${ packageName };";
    } { } "unstable-dynamic-access")
    (fixture "missing force reason" {
      "aspects/cli/shell/default.nix" = "x = lib.mkForce 1;";
    } { } "force-reason")
    (fixture "unregistered feature" {
      "aspects/default.nix" = "imports = [ ];";
      "aspects/cli/shell/default.nix" = "den.aspects.shell = {};";
    } { } "unregistered-feature")
    (fixture "feature directory without entrypoint" {
      "aspects/default.nix" = "imports = [ ];";
      "aspects/cli/rogue/private.nix" = "{}";
    } { } "missing-feature-entry")
    (fixture "duplicate aspect ID across features" {
      "aspects/default.nix" = "imports = [ ./cli/one ./desktop/two ];";
      "aspects/cli/one/default.nix" = "den.aspects.shared = {};";
      "aspects/desktop/two/default.nix" = "den.aspects.shared = {};";
    } { } "duplicate-aspect-name")
    (fixture "reserved entity ID" {
      "aspects/default.nix" = "imports = [ ./system/mayon ];";
      "aspects/system/mayon/default.nix" = "den.aspects.mayon = {};";
    } { reservedNames = [ "mayon" ]; } "reserved-aspect-name")
    (fixture "reserved attrset entity ID" {
      "aspects/default.nix" = "imports = [ ./system/identity ];";
      "aspects/system/identity/default.nix" = "den.aspects = { mayon = {}; };";
    } { reservedNames = [ "mayon" ]; } "reserved-aspect-name")
    (fixture "missing README" {
      "aspects/default.nix" = "imports = [ ./dev/example ];";
      "aspects/dev/example/default.nix" = "den.aspects.example = {};";
      "aspects/dev/example/contract.nix" = "{}";
    } { } "missing-feature-readme")
    (fixture "function class requires README" {
      "aspects/default.nix" = "imports = [ ./dev/example ];";
      "aspects/dev/example/default.nix" =
        "den.aspects.example = { homeManager = { home.file.x = {}; }; };";
    } { } "missing-feature-readme")
    (fixture "unused lib helper" { "lib/helper.nix" = "x: x"; } { } "unused-lib")
    (fixtureAbsent "inventory registration imports are allowed" {
      "inventory/hosts/demo/default.nix" = "imports = [ ./users/mayon.nix ../../users/mayon.nix ];";
    } { } "inventory-import")
    (fixtureAbsent "hardware and sops imports are allowed" {
      "inventory/hosts/demo/default.nix" =
        "imports = [ ./hardware-configuration.nix ./secrets.nix ];\nnixos.imports = [ inputs.sops-nix.nixosModules.sops ];";
    } { } "inventory-import")
    (fixtureAbsent "adjacent force reason is accepted" {
      "aspects/default.nix" = "imports = [ ./cli/shell ];";
      "aspects/cli/shell/default.nix" = "x = lib.mkForce 1; # force: fixture override\n";
    } { } "force-reason")
    (fixture "force directive inside a string is ignored" {
      "aspects/cli/shell/default.nix" = "note = \"# force: not a comment\";\nx = lib.mkForce 1;";
    } { } "force-reason")
    (fixtureAbsent "commented legacy name is ignored" {
      "aspects/default.nix" = "imports = [ ./cli/shell ];";
      "aspects/cli/shell/default.nix" = "# pkgs-unstable is only a note\nx = 1;";
    } { } "legacy-unstable-arg")
  ];
  allErrors = errors ++ (if includeFixtures then lib.concatLists fixtures else [ ]);
in
if returnErrors then
  allErrors
else if allErrors == [ ] then
  true
else
  throw "Architecture check failed:\n${builtins.concatStringsSep "\n" allErrors}"
