# Visual Studio Code

Installs the FHS VS Code package for the selected user and routes native editor runtime support through `editing-runtime-host`. It contributes the `vscode` Noctalia integration ID. It has no user appearance data dependency.

The FHS variant supplies the system libraries needed by extension-provided binaries; this avoids maintaining a partial `LD_LIBRARY_PATH` wrapper. `default.nix` and `vscode.nix` own the declarations and are private Nix files.

Removing the aspect removes VS Code, its integration contribution, and the runtime selection if no other editor needs it. It preserves VS Code settings, extensions, authentication, workspace state, and project files.
