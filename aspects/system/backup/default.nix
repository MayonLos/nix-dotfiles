_: {
  den.aspects.backup = {
    nixos =
      {
        config,
        lib,
        ...
      }:
      {
        # Local, versioned backup of user documents, pictures and the dotfiles
        # checkout. The repository lives on the same physical disk; it protects
        # against accidental edits/deletions, not disk loss or fire. A second
        # repository on another disk/account is still required for that.
        services.restic.backups.home = {
          repository = "/home/mayon/Backups/restic";
          passwordFile = config.sops.secrets.restic-password.path;
          paths = [
            "/home/mayon/Documents"
            "/home/mayon/Pictures"
            "/home/mayon/nix-dotfiles"
          ];
          exclude = [
            # Large generated/toolchain and game data, not user-authored docs.
            "/home/mayon/Documents/embedded"
            "/home/mayon/Documents/gtnh"
            "/home/mayon/Documents/gtnh-nuclear"
            "/home/mayon/Documents/gtnh-nuclear-refs"
            "**/.cache"
            "**/node_modules"
            "**/.venv"
            "**/target"
          ];
          initialize = true;
          extraBackupArgs = [
            "--compression"
            "max"
          ];
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
          ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "15m";
          };
        };

        # restic runs as root and initializes the repository; the parent must
        # exist first. The repository itself is created by restic.
        systemd.tmpfiles.rules = [
          "d /home/mayon/Backups 0700 root root -"
        ];
      };
  };
}
