{
  pkgs,
  nixos,
  appearance,
  ...
}:
let
  greeter = nixos.services.displayManager.noctalia-greeter;
in
{
  greeter-tech = pkgs.runCommand "greeter-tech-check" { } ''
    # Building this closure applies the patch and its fail-closed source checks.
    test -x ${greeter.package}/bin/noctalia-greeter
    test '${greeter.settings.appearance.font_family}' = '${appearance.fonts.mono}'
    test '${greeter.settings.session.default}' = Mango
    test '${greeter.settings.clock.time_format}' = '{:%H:%M}'
    touch "$out"
  '';
}
