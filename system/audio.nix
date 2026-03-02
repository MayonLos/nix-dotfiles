{
  ...
}:

{
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
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

  security.rtkit.enable = true;
}
