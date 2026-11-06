{ pkgs, home, ... }:
let
  service = home.systemd.user.services.game-tunnel;
  # Home Manager normalises ExecStart to a list.
  execStart = builtins.head (pkgs.lib.toList service.Service.ExecStart);
  config = builtins.elemAt (pkgs.lib.splitString " " execStart) 2;
in
assert !(service ? Install);
assert pkgs.lib.hasPrefix "${pkgs.frp}/bin/frpc -c /nix/store/" execStart;
{
  # Validates the generated client config with frpc itself, against a dummy
  # token file, and makes sure no token value is embedded in the store file.
  game-tunnel = pkgs.runCommand "game-tunnel-check" { nativeBuildInputs = [ pkgs.frp ]; } ''
    ! grep -E '^\s*token\s*=' ${config}
    grep -q 'tokenSource' ${config}
    grep -q '/run/secrets/' ${config}
    sed "s|/run/secrets/[A-Za-z0-9_-]*|$TMPDIR/token|" ${config} > frpc.toml
    printf dummy > "$TMPDIR/token"
    frpc verify -c frpc.toml
    touch $out
  '';
}
