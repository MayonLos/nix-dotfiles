{ lib, pkgs }:

# Activation helper for files the running application owns and rewrites
# (qt6ct/qt5ct configs, kitty's Noctalia include, zathura's Noctaliarc):
# create them once if absent, never overwrite what is already there.
rec {
  mkScript =
    path:
    {
      source ? null,
      mode ? "0644",
    }:
    ''
      if [ ! -e "${path}" ]; then
        run mkdir -p "$(dirname "${path}")"
        run ${pkgs.coreutils}/bin/install -m ${mode} ${
          if source == null then "/dev/null" else toString source
        } "${path}"
      fi
    '';

  mkActivation = path: opts: lib.hm.dag.entryAfter [ "writeBoundary" ] (mkScript path opts);
}
