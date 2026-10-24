{ inputs, pkgs }:
inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./tech-greeter.patch ];
  postPatch = (old.postPatch or "") + ''
    grep -F 'techMachineStatus()' src/greeter/greeter_surface.cpp
    grep -F 'FillMode::LinearGradient' src/greeter/greeter_surface.cpp
    grep -F 'm_techUnderline->setSize(inputWidth, 2.0f);' src/greeter/greeter_surface.cpp
    grep -F 'm_techStatus->setText(' src/greeter/greeter_surface.cpp
    grep -F 'charge_control_end_threshold' src/greeter/greeter_surface.cpp
    grep -F '/sys/bus/platform/drivers/ideapad_acpi' src/greeter/greeter_surface.cpp
    grep -F 'conservation_mode' src/greeter/greeter_surface.cpp
  '';
})
