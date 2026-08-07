{ pkgs-unstable, ... }:
{
  # Both packages come from unstable: stable 26.05 only has the IDE (at 1.23.2)
  # and no antigravity-cli at all, so the Home Manager modules' default
  # `pkgs.antigravity*` would be wrong here.
  programs = {
    antigravity = {
      enable = true;
      # FHS variant: the IDE pulls prebuilt binaries for extensions and language
      # servers, which need a normal filesystem layout to load.
      package = pkgs-unstable.antigravity-ide-fhs;
    };

    antigravity-cli = {
      enable = true;
      package = pkgs-unstable.antigravity-cli; # command is `agy`
    };
  };
}
