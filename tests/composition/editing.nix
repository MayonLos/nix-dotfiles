{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  system = "x86_64-linux";
  palette = import ../../aspects/appearance/appearance/onedark.nix;

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
          ../../aspects/appearance/appearance
          ../../aspects/dev/languages
          ../../aspects
        ];

        den = {
          systems = [ system ];
          schema.user.classes = [ "homeManager" ];
          hosts.${system} = {
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

          default = {
            nixos = {
              # Reuse the fixture pipeline package set, including unfree opt-ins.
              nixpkgs.pkgs = pkgs;
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

        };
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

  cppData = (import ../../aspects/dev/languages/contract.nix { inherit lib; }).defaults.cpp;
  contract = import ../../aspects/dev/languages/contract.nix { inherit lib; };
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
      assert(vim.deep_equal(servers.clangd.cmd, { "clangd", "--background-index", "--clang-tidy", "--header-insertion=never", "--completion-style=detailed", "--function-arg-placeholders=0" }))
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

  clangdIntegrationCheck = pkgs.writeText "editing-clangd-integration.lua" ''
    local ok, err = xpcall(function()
      assert(not package.loaded["vim.lsp"], "empty startup must defer LSP")
      vim.cmd.edit(vim.env.CONTRACT_PROJECT .. "/main.cpp")
      assert(vim.bo.filetype == "cpp", "C++ filetype detection is missing")
      assert(vim.deep_equal(vim.lsp.config.clangd.cmd, {
        "clangd", "--background-index", "--clang-tidy",
        "--header-insertion=never", "--completion-style=detailed", "--function-arg-placeholders=0",
      }), "production clangd command or arguments changed")
      assert(vim.lsp.is_enabled("clangd"), "C/C++ profile must enable clangd")

      local client
      assert(vim.wait(30000, function()
        client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
        return client and client.initialized
      end, 50), "production clangd did not attach")
      assert(
        vim.fs.normalize(client.config.root_dir) == vim.fs.normalize(vim.env.CONTRACT_PROJECT),
        "clangd selected the wrong project root"
      )

      local response = client:request_sync("textDocument/hover", {
        textDocument = { uri = vim.uri_from_bufnr(0) },
        position = { line = 0, character = 5 },
      }, 15000, 0)
      assert(response and response.result, "clangd returned no hover for the C++ function")
      local contents = response.result.contents
      assert(contents and (type(contents) == "string" or vim.tbl_isempty(contents) == false),
        "clangd hover response has no content")
      assert(vim.fn.writefile({ vim.json.encode(response.result) }, vim.env.CONTRACT_RESULT) == 0,
        "could not write the clangd hover artifact")
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

  profile=${runtimeHome editorAndCpp "hostB" "alice"}
  project="$TMPDIR/clangd-project"
  mkdir -p "$project" "$TMPDIR/lsp-home" "$TMPDIR/lsp-config" "$TMPDIR/lsp-cache" "$TMPDIR/lsp-state" "$out"
  cat > "$project/main.cpp" <<'CPP'
  int answer() { return 42; }
  int main() { return answer(); }
  CPP
  printf '[{"directory":"%s","arguments":["%s/bin/clang++","-std=c++20","-c","main.cpp"],"file":"%s/main.cpp"}]' \
    "$project" "$profile" "$project" > "$project/compile_commands.json"
  test -x "$profile/bin/clang++"
  test -x "$profile/bin/clangd"
  "$profile/bin/clang++" -std=c++20 -fsyntax-only "$project/main.cpp"
  HOME="$TMPDIR/lsp-home" \
    XDG_CONFIG_HOME="$TMPDIR/lsp-config" \
    XDG_CACHE_HOME="$TMPDIR/lsp-cache" \
    XDG_STATE_HOME="$TMPDIR/lsp-state" \
    PATH="$profile/bin:${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.git
      ]
    }" \
    CONTRACT_PROJECT="$project" \
    CONTRACT_RESULT="$out/hover.json" \
    "$profile/bin/nvim" --headless -c 'lua dofile("${clangdIntegrationCheck}")'
''
