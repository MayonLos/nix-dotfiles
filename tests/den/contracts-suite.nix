{
  evaluate,
  inputs,
  lib,
}:
let
  palette = import "${inputs.appearance}/onedark-darker.nix";
  tools = {
    terminal.argv = [ "kitty" ];
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
  settings = {
    appearance = palette;
    defaultTools = tools;
  };
  features = [
    "sample-kitty"
    "sample-neovim"
    "sample-gui-apps"
    "default-tools"
    "cpp-support"
  ];
  baseline = evaluate { };
  dataOnly = evaluate { userSettings."alice@probe-a" = settings; };
  selected = evaluate {
    userSettings."alice@probe-a" = settings;
    featureChoices."alice@probe-a" = features;
  };
  mirrored = evaluate {
    userSettings."bob@probe-b" = settings // {
      appearance = palette // {
        bg = "#242830";
      };
    };
    featureChoices."bob@probe-b" = features;
  };
  defaultsOnly = evaluate {
    userSettings."alice@probe-a" = settings;
    featureChoices."alice@probe-a" = [ "default-tools" ];
  };
  quoted = evaluate {
    userSettings."alice@probe-a".defaultTools = tools // {
      terminal.argv = [
        "kitty"
        "--class"
        "work space"
        "--title"
        "literal $HOME; $(touch injected)"
      ];
    };
    featureChoices."alice@probe-a" = [ "default-tools" ];
  };
  languageOnly = evaluate { featureChoices."alice@probe-a" = [ "cpp-support" ]; };
  editorOnly = evaluate { featureChoices."alice@probe-a" = [ "sample-neovim" ]; };
  repeated = evaluate {
    userSettings."alice@probe-a" = settings;
    featureChoices."alice@probe-a" = features ++ [ "sample-repeat-cpp" ];
  };
  conflicting = evaluate {
    featureChoices."alice@probe-a" = [
      "sample-neovim"
      "cpp-support"
      "sample-conflicting-cpp"
    ];
  };
  home =
    hosts: host: user:
    hosts.${host}.config.home-manager.users.${user};
  base = home baseline "probe-a" "alice";
  chosen = home selected "probe-a" "alice";
  inspect = hm: {
    kitty = hm.programs.kitty.enable;
    neovim = hm.programs.neovim.enable;
    kittySettings = hm.programs.kitty.settings;
    lua = hm.programs.neovim.initLua;
    packages = map (p: p.pname or (lib.getName p)) hm.home.packages;
    variables = hm.home.sessionVariables;
    defaults = hm.xdg.mimeApps.defaultApplications;
    files = builtins.attrNames hm.xdg.configFile;
  };
  hostInspect =
    hosts: host: lib.genAttrs [ "alice" "bob" ] (homeName: inspect (home hosts host homeName));
  schema =
    modules:
    (lib.evalModules {
      modules = [
        "${inputs.appearance}/contract.nix"
        "${inputs.default-tools}/contract.nix"
      ]
      ++ modules;
    }).config;
  fails = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  inherit ((import "${inputs.languages}/contract.nix" { inherit lib; })) collect;
  cpp = import "${inputs.languages}/cpp-data.nix";
  results = {
    dataDoesNotEnableFeatures = hostInspect dataOnly "probe-a" == hostInspect baseline "probe-a";
    twoPaletteConsumers =
      chosen.programs.kitty.settings.background == palette.bg
      && lib.hasInfix palette.bg chosen.programs.neovim.initLua
      && chosen.xdg.configFile ? "kitty/kitty.conf"
      && chosen.xdg.configFile ? "nvim/init.lua";
    otherUserUntouched =
      inspect (home selected "probe-a" "bob") == inspect (home baseline "probe-a" "bob");
    otherHostUntouched = hostInspect selected "probe-b" == hostInspect baseline "probe-b";
    perBindingSelection =
      (home mirrored "probe-b" "bob").programs.kitty.settings.background == "#242830"
      && lib.hasInfix "#242830" (home mirrored "probe-b" "bob").programs.neovim.initLua
      && hostInspect mirrored "probe-a" == hostInspect baseline "probe-a"
      && inspect (home mirrored "probe-b" "alice") == inspect (home baseline "probe-b" "alice");
    cliAndGuiEditor =
      lib.hasSuffix "/bin/workspace-editor" chosen.home.sessionVariables.EDITOR
      && chosen.home.sessionVariables.VISUAL == chosen.home.sessionVariables.EDITOR
      && chosen.xdg.mimeApps.defaultApplications."text/plain" == [ "code.desktop" ];
    sessionVariableOwnership =
      !(chosen.systemd.user.sessionVariables ? DEN_IDENTITY)
      && chosen.systemd.user.sessionVariables.EDITOR == chosen.home.sessionVariables.EDITOR;
    browserAndFiles =
      chosen.xdg.mimeApps.defaultApplications."x-scheme-handler/https" == [ "firefox.desktop" ]
      && chosen.xdg.mimeApps.defaultApplications."inode/directory" == [ "thunar.desktop" ];
    defaultsDoNotInstallApplications =
      !(home defaultsOnly "probe-a" "alice").programs.kitty.enable
      && !(home defaultsOnly "probe-a" "alice").programs.neovim.enable
      && !lib.any (name: lib.elem name (inspect (home defaultsOnly "probe-a" "alice")).packages) [
        "kitty"
        "neovim"
        "firefox"
        "thunar"
        "vscode"
      ];
    languageWithoutEditor =
      !(home languageOnly "probe-a" "alice").programs.neovim.enable
      && !(lib.elem "nvim/init.lua" (inspect (home languageOnly "probe-a" "alice")).files)
      && lib.elem "clang-tools" (inspect (home languageOnly "probe-a" "alice")).packages;
    editorWithoutLanguage =
      !lib.hasInfix "--clang-tidy" (home editorOnly "probe-a" "alice").programs.neovim.initLua
      && !lib.elem "clang-tools" (inspect (home editorOnly "probe-a" "alice")).packages;
    identicalContributionIsIdempotent =
      chosen.programs.neovim.initLua == (home repeated "probe-a" "alice").programs.neovim.initLua;
    conflictingLanguageRejected = fails (home conflicting "probe-a" "alice").programs.neovim.initLua;
    orderedCommands =
      (collect [
        cpp
        cpp
      ]).servers.clangd.cmd == cpp.neovim.servers.clangd.cmd
      &&
        (schema [
          { defaultTools = tools; }
          { defaultTools = tools; }
        ]).defaultTools.editor.argv == [ "nvim" ];
    conflictingCommandRejected =
      fails
        (schema [
          { defaultTools = tools; }
          { defaultTools.editor.argv = [ "other-editor" ]; }
        ]).defaultTools.editor.argv;
    malformedDataRejected =
      fails
        (schema [
          {
            appearance = palette // {
              bg = "invalid-color";
            };
          }
        ]).appearance.bg
      && fails (schema [ { defaultTools.editor.argv = [ ]; } ]).defaultTools.editor.argv
      && fails (schema [ { defaultTools.guiTextEditor = "bad desktop id"; } ]).defaultTools.guiTextEditor;
    sharedServerAcrossLanguages =
      (collect [
        cpp
        (cpp // { id = "c"; })
      ]).servers.clangd == (collect [ cpp ]).servers.clangd;
    conflictingServerAcrossLanguages =
      fails
        (collect [
          cpp
          (lib.recursiveUpdate cpp {
            id = "c";
            neovim.servers.clangd.cmd = [ "other-clangd" ];
          })
        ]).servers.clangd.cmd;
    fixtureHasSingleThemeOwner =
      !lib.any (name: chosen.xdg.configFile ? ${name}) [
        "kitty/mayon.conf"
        "kitty/themes/noctalia.conf"
      ];
    noGraphicalSession =
      lib.all
        (
          hosts:
          lib.all
            (
              host:
              let
                c = hosts.${host}.config;
              in
              !c.services.xserver.enable && !c.services.displayManager.enable && !c.programs.sway.enable
            )
            [
              "probe-a"
              "probe-b"
            ]
        )
        [
          baseline
          selected
          mirrored
          defaultsOnly
          languageOnly
        ];
  };
in
{
  inherit results palette tools;
  homes = {
    selected = chosen;
    editorOnly = home editorOnly "probe-a" "alice";
    quoted = home quoted "probe-a" "alice";
  };
  observations = {
    selected = inspect chosen;
    baseline = inspect base;
  };
  passed =
    lib.assertMsg (lib.all (x: x) (lib.attrValues results))
      "Den contract failures: ${builtins.toJSON (lib.filterAttrs (_: value: !value) results)}";
}
