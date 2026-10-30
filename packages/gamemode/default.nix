{ gamemode, runCommandCC }:

gamemode.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./ppd-governor.patch
    ./client-disconnect.patch
  ];
  passthru = (old.passthru or { }) // {
    runtimeProbe = runCommandCC "gamemode-close-fds" { } ''
      mkdir -p "$out/bin"
      $CC -Wall -Wextra -Werror ${./tests/close-fds.c} -o "$out/bin/gamemode-close-fds"
    '';
  };
})
