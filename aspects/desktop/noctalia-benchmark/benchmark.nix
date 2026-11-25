{ pkgs, ... }:
let
  targets = [
    "mango-session.target"
    "umbriel-session.target"
    "hyprland-session.target"
  ];
  benchmark = pkgs.writeShellApplication {
    name = "desktop-benchmark";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.procps
      pkgs.systemd
    ];
    text = builtins.readFile ./benchmark.sh;
  };
in
{
  home.packages = [ benchmark ];

  # One-shot collector: after a login, sample the idle desktop twice (90s and
  # 300s) so the three sessions can be compared with the same script.
  systemd.user.services.desktop-benchmark = {
    Unit = {
      Description = "Collect idle desktop session benchmarks";
      PartOf = targets;
      After = targets;
    };
    Service = {
      Type = "exec";
      ExecStart = "${benchmark}/bin/desktop-benchmark";
      TimeoutStartSec = 900;
    };
    Install.WantedBy = targets;
  };
}
