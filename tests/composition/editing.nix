{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  system = "x86_64-linux";
  palette = import ../../aspects/appearance/onedark-darker.nix;

  bindings = [
    "alice@hostA"
    "bob@hostA"
    "alice@hostB"
    "bob@hostB"
  ];
  evaluate =
    selected:
    (inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      { den, ... }:
      {
        imports = [
          inputs.den.flakeModule
          ../../aspects/appearance
          ../../aspects/languages
          ../../aspects/editing
        ];

        den.systems = [ system ];
        den.schema.user.classes = [ "homeManager" ];
        den.hosts.${system} = {
          hostA.users = {
            alice = {
              appearance = palette;
            };
            bob = {
              appearance = palette;
            };
          };
          hostB.users = {
            alice = {
              appearance = palette;
            };
            bob = {
              appearance = palette;
            };
          };
        };

        den.default = {
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

        den.aspects = lib.genAttrs bindings (
          binding:
          let
            user = builtins.head (lib.splitString "@" binding);
          in
          {
            user.isNormalUser = true;
            homeManager = {
              home.username = user;
              home.homeDirectory = "/home/${user}";
            };
            includes = lib.optionals (builtins.hasAttr binding selected) (
              let
                chosen = selected.${binding} or [ ];
              in
              map (name: den.aspects.${name}) chosen
            );
          }
        );

      }
    )).nixosConfigurations;

  editorOnly = evaluate { "alice@hostA" = [ "neovim" ]; };
  cppOnly = evaluate { "bob@hostA" = [ "cpp-support" ]; };
  editorAndCpp = evaluate {
    "alice@hostB" = [
      "neovim"
      "cpp-support"
    ];
  };
  unselected = evaluate { };

  host = configs: name: configs.${name}.config;
  home =
    configs: hostName: user:
    (host configs hostName).home-manager.users.${user};
  hasPackage = hm: name: builtins.elem name (map (p: p.pname or (lib.getName p)) hm.home.packages);

  editorHome = home editorOnly "hostA" "alice";
  cppHome = home cppOnly "hostA" "bob";
  combinedHome = home editorAndCpp "hostB" "alice";
  untouchedHome = home unselected "hostB" "bob";
  runtimeHome =
    configs: hostName: user:
    (host configs hostName).home-manager.users.${user}.home.path;

  cppData = import ../../aspects/languages/cpp-data.nix;
  contract = import ../../aspects/languages/contract.nix { inherit lib; };
  conflictFails =
    contributions: !(builtins.tryEval (builtins.deepSeq (contract.collect contributions) true)).success;
  conflict = contribution: lib.recursiveUpdate cppData contribution;

  results = {
    editorOnlyHasNoLanguageTools =
      hasPackage editorHome "neovim"
      && !hasPackage editorHome "clang-tools"
      && !(editorHome.programs.java.enable or false);

    languageOnlyHasNoEditor =
      !hasPackage cppHome "neovim"
      && !(cppHome.xdg.configFile ? "nvim/init.lua")
      && hasPackage cppHome "clang-tools";

    combinedBindingGetsEditorAndCpp =
      hasPackage combinedHome "neovim"
      && hasPackage combinedHome "clang-tools"
      && combinedHome.xdg.configFile ? "nvim/init.lua";

    unselectedBindingStaysEmpty =
      !(hasPackage untouchedHome "neovim")
      && !(hasPackage untouchedHome "clang-tools")
      && !(untouchedHome.xdg.configFile ? "nvim/init.lua");

    selectionDoesNotCrossAccountsOrHosts =
      !(hasPackage (home editorOnly "hostA" "bob") "neovim")
      && !(hasPackage (home editorOnly "hostA" "bob") "clang-tools")
      && !(hasPackage (home editorOnly "hostB" "alice") "neovim")
      && !(hasPackage (home editorOnly "hostB" "alice") "clang-tools")
      && !(hasPackage (home cppOnly "hostA" "alice") "neovim")
      && !(hasPackage (home cppOnly "hostB" "alice") "clang-tools")
      && !(hasPackage (home editorAndCpp "hostA" "alice") "neovim")
      && !(hasPackage (home editorAndCpp "hostB" "bob") "clang-tools");

    noEditorHostOrSessionLeak =
      !(host editorOnly "hostA").programs.nix-ld.enable
      && !(host editorOnly "hostB").programs.nix-ld.enable
      && !(host cppOnly "hostA").programs.nix-ld.enable
      && !(host editorAndCpp "hostB").services.greetd.enable
      && !(host editorAndCpp "hostB").services.xserver.enable
      && !((host editorAndCpp "hostB").programs.mango.enable or false)
      && !(combinedHome.programs.kitty.enable or false)
      && !(combinedHome.programs ? noctalia)
      && !((host editorAndCpp "hostB") ? sops)
      && !(lib.hasInfix "/run/secrets" (combinedHome.home.sessionVariables.EDITOR or ""))
      && (host editorAndCpp "hostB").users.users.alice.extraGroups == [ ];

    orderedCommandConflictRejected = conflictFails [
      cppData
      (conflict { neovim.servers.clangd.cmd = [ "other-clangd" ]; })
    ];
    orderedRootConflictRejected = conflictFails [
      cppData
      (conflict { neovim.servers.clangd.root_markers = [ ".git" ]; })
    ];
    orderedFormatterConflictRejected = conflictFails [
      cppData
      (conflict { neovim.formatters.cpp = [ "other-format" ]; })
    ];
    filetypesMergeAsASet =
      lib.sort builtins.lessThan
        (contract.collect [
          cppData
          (conflict {
            neovim.servers.clangd.filetypes = [
              "c"
              "cuda"
              "custom-cpp"
            ];
          })
        ]).servers.clangd.filetypes == lib.sort builtins.lessThan [
        "c"
        "cpp"
        "objc"
        "objcpp"
        "cuda"
        "custom-cpp"
      ];
  };

  runtimeCheck = pkgs.writeText "editing-composition.lua" ''
    local ok, err = xpcall(function()
    local generated = require("mayon.generated").languages
    local servers = require("mayon.lsp.servers").servers
    if vim.env.EXPECT_CPP == "1" then
      assert(vim.tbl_count(servers) == 1 and servers.clangd, "C/C++ selection must enable only clangd")
      assert(vim.deep_equal(servers.clangd.cmd, { "clangd", "--background-index", "--clang-tidy" }))
      assert(vim.deep_equal(servers.clangd.filetypes, { "c", "cpp", "objc", "objcpp", "cuda" }))
      assert(vim.deep_equal(generated.formatters, { c = { "clang-format" }, cpp = { "clang-format" } }))
      assert(vim.tbl_isempty(generated.linters))
      assert(vim.fn.exepath("clangd") == vim.env.CLANGD_SPY, "clangd lookup must follow the project PATH")
    else
      assert(vim.tbl_isempty(servers), "editor without language selections must have no LSP servers")
      assert(vim.tbl_isempty(generated.formatters), "editor without language selections must have no formatters")
      assert(vim.tbl_isempty(generated.linters), "editor without language selections must have no linters")
      assert(not generated.servers.jdtls and not generated.servers.jdt_language_server, "Java server leaked")
    end
    end, debug.traceback)
    if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
    vim.cmd("qa!")
  '';

  passed = lib.all (value: value) (builtins.attrValues results);
  report = pkgs.writeText "den-editing-composition.json" (builtins.toJSON results);
in
assert lib.assertMsg passed
  "Editing composition failures: ${builtins.toJSON (lib.filterAttrs (_: value: !value) results)}";
pkgs.runCommand "den-editing-composition" { } ''
  mkdir -p "$out"
  cp ${report} "$out/results.json"

  spy="$TMPDIR/project-bin"
  mkdir -p "$spy" "$TMPDIR/home" "$TMPDIR/config" "$TMPDIR/cache" "$TMPDIR/state"
  cat > "$spy/clangd" <<'SH'
  #!${pkgs.runtimeShell}
  exit 0
  SH
  chmod +x "$spy/clangd"

  run_editor() {
    profile="$1"
    expected="$2"
    test -x "$profile/bin/nvim"
    HOME="$TMPDIR/home" \
      XDG_CONFIG_HOME="$TMPDIR/config" \
      XDG_CACHE_HOME="$TMPDIR/cache" \
      XDG_STATE_HOME="$TMPDIR/state" \
      PATH="$spy:${
        pkgs.lib.makeBinPath [
          pkgs.coreutils
          pkgs.git
        ]
      }" \
      EXPECT_CPP="$expected" \
      CLANGD_SPY="$spy/clangd" \
      "$profile/bin/nvim" --headless -c 'lua dofile("${runtimeCheck}")'
  }

  run_editor ${runtimeHome editorOnly "hostA" "alice"} 0
  run_editor ${runtimeHome editorAndCpp "hostB" "alice"} 1
''
