# Workspace task

Installs the `workspace-task` command for long-running commands that should block ordinary sleep while they run. It has no entity data input and can be selected by command-line or desktop features through Den includes.

The wrapper delegates to `systemd-inhibit --what=sleep --mode=block`; it passes the command and arguments through and releases the inhibitor when the child exits. It does not disable screen locking. `default.nix` and the private package factory `package.nix` own the output; neither is a public package API.

Removing the feature removes the command on activation. It does not stop any already-running process or change user project data.
