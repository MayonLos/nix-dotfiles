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
    wireplumber = {
      enable = true;
      # Any capture of a headset's virtual source (pavucontrol's input peak
      # meters, a chat app probing devices) otherwise flips A2DP to HFP:
      # 8/16 kHz mono "radio" audio that also stalled and dropped the link.
      # Headset mics stay available by selecting the HFP profile by hand.
      extraConfig."51-bluetooth-no-autoswitch"."wireplumber.settings" = {
        "bluetooth.autoswitch-to-headset-profile" = false;
      };
    };
    jack.enable = true;
    # No always-on echo-cancel module: nothing used its source, yet it held
    # the built-in mic open and pulled the default sink into the mic's
    # 256-sample graph, starving Bluetooth A2DP (constant dropouts).
    # Chat/meeting apps and browsers run their own AEC.
    extraConfig = {
      # Desktop notifications provide their own sounds. The legacy X11 bell
      # module holds an Xwayland connection until PipeWire exits (later than
      # Mango), generating X I/O errors during logout. No session uses that
      # system bell; PCM/Pulse/JACK and desktop notification sounds are intact.
      pipewire."90-no-x11-bell"."context.properties"."module.x11.bell" = false;
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
