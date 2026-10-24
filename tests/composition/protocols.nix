{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  system = "x86_64-linux";
  paletteA = import ../../aspects/appearance/appearance/onedark.nix;
  paletteB = paletteA // {
    bg = "#20242a";
    deep = "#161a20";
  };
  tools = {
    terminal.argv = [
      "kitty"
      "--class"
      "work space"
      "--title"
      "literal $HOME; $(touch injected)"
    ];
    editor.argv = [ "nvim" ];
    browser = {
      argv = [ "firefox" ];
      desktopId = "firefox.desktop";
    };
    fileManager = {
      argv = [ "thunar" ];
      desktopId = "thunar.desktop";
    };
    guiTextEditor = "code.desktop";
  };

  bindings = [
    "alice@hostA"
    "bob@hostA"
    "alice@hostB"
    "bob@hostB"
  ];

  evaluate =
    {
      withData ? true,
      selected ? { },
    }:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
          # Register the production aspect declarations, while selecting only
          # their real terminal/default-tools consumers below.
          ../../aspects/cli/shell
          ../../aspects/cli/terminal
          ../../aspects/system/default-tools
          ../../aspects/workspace/project-workbench
        ];

        den = {
          systems = [ system ];
          schema.user.classes = [ "homeManager" ];
          hosts.${system} = {
            hostA.users = {
              alice = lib.optionalAttrs withData {
                appearance = paletteA // {
                  reducedMotion = true;
                };
                defaultTools = tools;
                workspaceProjects.sample = {
                  directory = "/home/alice/project space";
                  label = "Example workspace";
                };
              };
              bob = lib.optionalAttrs withData {
                appearance = paletteA;
                defaultTools = tools;
              };
            };
            hostB.users = {
              alice = lib.optionalAttrs withData {
                appearance = paletteA;
                defaultTools = tools;
              };
              bob = lib.optionalAttrs withData {
                appearance = paletteB // {
                  reducedMotion = false;
                };
                defaultTools = tools;
              };
            };
          };

          default = {
            nixos = {
              system.stateVersion = "26.05";
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
              };
              home-manager.useGlobalPkgs = true;
              home-manager.extraSpecialArgs.inputs = inputs;
            };
            homeManager.home.stateVersion = "26.05";
          };

          aspects = lib.genAttrs bindings (
            binding:
            let
              user = builtins.head (lib.splitString "@" binding);
              includes = selected.${binding} or [ ];
            in
            {
              user.isNormalUser = true;
              homeManager.home = {
                username = user;
                homeDirectory = "/home/${user}";
              };
              includes = map (name: den.aspects.${name}) includes;
            }
          );
        };
      }
    )).nixosConfigurations;

  baseline = evaluate { withData = false; };
  dataOnly = evaluate { };
  selected = evaluate {
    selected = {
      "alice@hostA" = [
        "terminal"
        "default-tools"
        "project-workbench"
      ];
      "bob@hostB" = [
        "terminal"
        "default-tools"
      ];
      "alice@hostB" = [ "default-tools" ];
    };
  };

  host = configs: name: configs.${name}.config;
  home =
    configs: hostName: user:
    (host configs hostName).home-manager.users.${user};
  packages = hm: map (package: package.outPath) hm.home.packages;
  packageNames = hm: map (package: package.pname or (lib.getName package)) hm.home.packages;
  wrapper =
    hm: lib.findFirst (package: (package.name or "") == "workspace-terminal") null hm.home.packages;

  baselineAliceA = home baseline "hostA" "alice";
  dataAliceA = home dataOnly "hostA" "alice";
  selectedAliceA = home selected "hostA" "alice";
  selectedBobB = home selected "hostB" "bob";
  defaultsAliceB = home selected "hostB" "alice";
  terminalWrapper = wrapper selectedAliceA;

  evaluateSchema = modules: (lib.evalModules { inherit modules; }).config;
  protocolSchema = [
    ../../aspects/appearance/appearance/contract.nix
    ../../aspects/system/default-tools/contract.nix
    ../../aspects/workspace/project-workbench/contract.nix
  ];
  schema = modules: evaluateSchema (protocolSchema ++ modules);
  fails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;

  sameTools = schema [
    { defaultTools = tools; }
    { defaultTools = tools; }
  ];
  conflictingTools = schema [
    {
      defaultTools.terminal.argv = [
        "kitty"
        "--class"
        "one"
      ];
    }
    {
      defaultTools.terminal.argv = [
        "kitty"
        "--title"
        "two"
      ];
    }
  ];
  badArgv = schema [ { defaultTools.terminal.argv = [ ]; } ];
  badDesktopId = schema [ { defaultTools.guiTextEditor = "code desktop"; } ];
  badPaletteType = schema [ { appearance.bg = 123; } ];
  badCjkType = schema [
    {
      appearance = paletteA // {
        fonts = paletteA.fonts // {
          cjk = 42;
        };
      };
    }
  ];
  missingCjk = schema [
    {
      appearance = paletteA // {
        fonts = builtins.removeAttrs paletteA.fonts [ "cjk" ];
      };
    }
  ];
  badReducedMotionType = schema [ { appearance.reducedMotion = "yes"; } ];
  defaultAppearance = schema [ { appearance = builtins.removeAttrs paletteA [ "reducedMotion" ]; } ];
  badProjectDirectory = schema [
    {
      workspaceProjects.sample = {
        directory = "relative/path";
        label = "Sample";
      };
    }
  ];

  cpp = (import ../../aspects/dev/languages/contract.nix { inherit lib; }).defaults.cpp;
  languageContract = import ../../aspects/dev/languages/contract.nix { inherit lib; };
  sharedServer = languageContract.collect [
    cpp
    (cpp // { id = "second-cpp-client"; })
  ];
  conflictingServer = languageContract.collect [
    cpp
    (lib.recursiveUpdate cpp {
      id = "different-cpp-client";
      neovim.servers.clangd.cmd = [ "other-clangd" ];
    })
  ];

  untouchedBindings = [
    [
      (home dataOnly "hostA" "bob")
      (home baseline "hostA" "bob")
    ]
    [
      (home dataOnly "hostB" "alice")
      (home baseline "hostB" "alice")
    ]
    [
      (home dataOnly "hostB" "bob")
      (home baseline "hostB" "bob")
    ]
  ];
  dataDoesNotEnableFeatures =
    packages dataAliceA == packages baselineAliceA
    && !(dataAliceA.programs.kitty.enable or false)
    && !(dataAliceA.xdg.configFile ? "kitty/kitty.conf")
    && lib.all (
      pair: packages (builtins.elemAt pair 0) == packages (builtins.elemAt pair 1)
    ) untouchedBindings;

  selectedPaletteA = selectedAliceA.xdg.configFile."kitty/kitty.conf".text or "";
  selectedPaletteB = selectedBobB.xdg.configFile."kitty/kitty.conf".text or "";

  results = {
    projectEntriesAreBindingScopedAndRemovedWithConsumer =
      selectedAliceA.xdg.desktopEntries ? workspace-project-sample
      && !(selectedBobB.xdg.desktopEntries ? workspace-project-sample)
      && !((home selected "hostB" "alice").xdg.desktopEntries ? workspace-project-sample)
      && !(dataAliceA.xdg.desktopEntries ? workspace-project-sample)
      && !(baselineAliceA.xdg.desktopEntries ? workspace-project-sample);
    dataOnlyDoesNotInstallApplications =
      dataDoesNotEnableFeatures
      && lib.all (name: !(builtins.elem name (packageNames defaultsAliceB))) [
        "kitty"
        "firefox"
        "thunar"
        "code"
        "vscode"
      ]
      && !(defaultsAliceB.programs.kitty.enable or false)
      && !(defaultsAliceB.xdg.configFile ? "kitty/kitty.conf");

    bindingsReceiveTheirOwnPalettes =
      lib.hasInfix "background ${paletteA.deep}" selectedPaletteA
      && lib.hasInfix "background ${paletteB.deep}" selectedPaletteB
      && !(lib.hasInfix "background ${paletteB.deep}" selectedPaletteA)
      && !(lib.hasInfix "background ${paletteA.deep}" selectedPaletteB)
      && lib.hasInfix "cursor_blink_interval 0\n" selectedPaletteA
      && lib.hasInfix "cursor_blink_interval 0.5\n" selectedPaletteB
      && lib.hasInfix "cursor_trail 0\n" selectedPaletteA
      && lib.hasInfix "cursor_trail 1\n" selectedPaletteB;

    invalidProtocolDataRejected =
      fails badArgv.defaultTools.terminal.argv
      && fails badDesktopId.defaultTools.guiTextEditor
      && fails badPaletteType.appearance.bg
      && fails badReducedMotionType.appearance.reducedMotion
      && fails badCjkType.appearance.fonts.cjk
      && fails missingCjk.appearance.fonts.cjk
      && fails badProjectDirectory.workspaceProjects.sample.directory
      && defaultAppearance.appearance.reducedMotion == false;

    identicalDataIsIdempotent = sameTools.defaultTools == tools;

    conflictingOrderedArgvRejected = fails conflictingTools.defaultTools.terminal.argv;

    languageServersShareOnlyEqualOrderedCommands =
      sharedServer.languages ? cpp
      && sharedServer.languages ? second-cpp-client
      && sharedServer.servers.clangd.cmd == cpp.neovim.servers.clangd.cmd
      && fails conflictingServer.servers.clangd.cmd;
  };

  terminalConfig = pkgs.writeText "protocols-kitty.conf" selectedPaletteA;
  runtimeCheck = pkgs.writeShellScript "protocols-terminal-wrapper-check" ''
    set -eu
    spy="$TMPDIR/spy-bin"
    work="$TMPDIR/work space"
    mkdir -p "$spy" "$work"
    cat > "$spy/kitty" <<'SH'
    #!${pkgs.runtimeShell}
    set -eu
    {
      printf 'argc=%s\n' "$#"
      for arg in "$@"; do printf 'arg=<%s>\n' "$arg"; done
      printf 'cwd=<%s>\n' "$PWD"
    } > "$CAPTURE"
    SH
    chmod +x "$spy/kitty"
    (
      cd "$work"
      PATH="$spy" CAPTURE="$TMPDIR/capture" \
        ${terminalWrapper}/bin/workspace-terminal \
        "" 'space "quote"' 'literal $HOME; $(touch injected)'
    )
    cat > "$TMPDIR/expected" <<'EOF'
    argc=7
    arg=<--class>
    arg=<work space>
    arg=<--title>
    arg=<literal $HOME; $(touch injected)>
    arg=<>
    arg=<space "quote">
    arg=<literal $HOME; $(touch injected)>
    EOF
    printf 'cwd=<%s>\n' "$work" >> "$TMPDIR/expected"
    diff -u "$TMPDIR/expected" "$TMPDIR/capture"
    test ! -e "$work/injected"
    grep -Fx 'background ${paletteA.deep}' ${terminalConfig} >/dev/null
    mkdir -p "$out"
    cp ${terminalConfig} "$out/kitty.conf"
    printf '%s\n' 'wrapper argv and cwd verified' > "$out/runtime.txt"
  '';

  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-protocol-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Protocol composition failures: ${builtins.toJSON (lib.filterAttrs (_: value: !value) results)}";
pkgs.runCommand "den-protocol-composition" { } ''
  ${runtimeCheck}
  mkdir -p "$out"
  cp ${report} "$out/results.json"
''
