# Neovim project templates

These files are optional, project-local starting points. Copy one into the
matching project; Neovim does not install templates or change project files.

## OpenComputers LuaLS configuration

Copy `opencomputers.luarc.json` to an OpenComputers project's root as
`.luarc.json`. It declares only the globals provided by the OpenComputers
runtime. Ordinary Lua projects do not inherit these names or the Neovim
configuration's `vim` and `Snacks` globals.

If the project already has a `.luarc.json`, merge the `diagnostics.globals`
entries into it instead of replacing the project's runtime, library, or other
LuaLS settings. Add project-specific type stub directories to
`workspace.library` in that project's own file when needed.
