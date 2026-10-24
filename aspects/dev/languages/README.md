# Language toolchains and editor data

Registers language features and the `editorLanguages` quirk. Selecting a language installs its tools and contributes typed editor data; data does not install or enable an editor. The Neovim aspect consumes contributions only when selected.

`contract.nix` is the public data interface and exports `defaults` plus `collect`, which validates and merges contributions by stable language ID. `data.nix` and `cpp-data.nix` are private implementation data. Other Nix files here are private. The registered language features cover C/C++, Java, Python, Lua, LaTeX, and MATLAB; project flakes remain responsible for project-specific SDK versions and build files.

The public collector exposes server, formatter, and linter configuration; ordered commands remain whole values and conflicting definitions fail instead of concatenating. C/C++ Clang, LLD, and clang-tools use the same `llvmPackages`; Java provides JDK and shell selection logic; Python, Lua, LaTeX, and MATLAB tools install only when selected. Checks through the consuming features cover language/editor combinations, conflicts, selection isolation, and a small real clangd workload; they do not cover every project, cross-compilation build, or an applied desktop.

The language feature owns `default.nix`, `contract.nix`, and its tool modules; except for the `defaults` and `collect` exports, the Nix files are private. Removing a language removes its packages and contribution after activation. It preserves project files, generated build databases, SDKs in project-local stores, and editor/user history. Removing an editor leaves selected language tools available if the language features remain selected. Each execution record is indexed from [the history log](../../../docs/history/den-execution.md).
