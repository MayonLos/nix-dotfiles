{ lib, ... }:

{
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      # programs/steam.nix in nixpkgs assigns this *plainly* (not mkDefault) as
      # `alsa.support32Bit = alsa.enable` whenever Steam is on, which it is.
      # The two agree today; setting `false` here would be a conflicting-
      # definition eval error, not a silent override. Disable it in steam.nix.
      support32Bit = true;
    };
    pulse.enable = true;
    wireplumber.enable = true;
    jack.enable = true;
    extraConfig = {
      pipewire."90-echo-cancel" = {
        "context.modules" = [
          {
            name = "libpipewire-module-echo-cancel";
            args = {
              "library.name" = "aec/libspa-aec-webrtc";
              "source.props" = {
                "node.name" = "echo_cancelled_source";
                "node.description" = "Echo Cancelled Source";
              };
              "sink.props" = {
                "node.name" = "echo_cancelled_sink";
                "node.description" = "Echo Cancelled Sink";
              };
            };
          }
        ];
      };

      pipewire-pulse."91-qq-wechat-compat" = {
        "pulse.rules" = [
          {
            matches = [
              { "application.process.binary" = "qq"; }
              { "application.process.binary" = "~wechat.*"; }
            ];
            actions = {
              quirks = [ "force-s16-info" ];
            };
          }
        ];
      };
    };
  };

  # Install shared audio support once, but do not activate sockets in every
  # account's manager. The selected session requests these units explicitly.
  # force: Only selected desktop targets request the upstream PipeWire sockets.
  systemd.user.sockets.pipewire.wantedBy = lib.mkForce [ ];
  # force: Only selected desktop targets request the upstream PipeWire sockets.
  systemd.user.sockets.pipewire-pulse.wantedBy = lib.mkForce [ ];

  security.rtkit.enable = true;
}
