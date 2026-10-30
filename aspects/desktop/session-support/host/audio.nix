{ lib, pkgs, ... }:

let
  # Manual counterpart of the disabled autoswitch: `headset-mic on` moves the
  # connected Bluetooth headset to HFP with mSBC (16 kHz wideband mic) and makes
  # its mic the default source; `off` returns to A2DP; `toggle` flips.
  headsetMic = pkgs.writeShellApplication {
    name = "headset-mic";
    runtimeInputs = [
      pkgs.jq
      pkgs.libnotify
      pkgs.pipewire
      pkgs.wireplumber
    ];
    text = ''
      dump=$(pw-dump)
      card=$(jq -r 'first(.[] | select(.type == "PipeWire:Interface:Device"
        and ((.info.props["device.name"] // "") | startswith("bluez_card"))) | .id) // empty' <<<"$dump")
      if [ -z "$card" ]; then
        notify-send -a 耳机 "没有已连接的蓝牙耳机"
        exit 1
      fi
      profile() {
        jq -r --argjson c "$card" --arg n "$1" 'first(.[] | select(.id == $c)
          | .info.params.EnumProfile[] | select(.name == $n) | .index) // empty' <<<"$dump"
      }
      active=$(jq -r --argjson c "$card" 'first(.[] | select(.id == $c) | .info.params.Profile[0].name) // ""' <<<"$dump")
      mode=''${1:-toggle}
      if [ "$mode" = toggle ]; then
        case "$active" in headset-head-unit*) mode=off ;; *) mode=on ;; esac
      fi
      if [ "$mode" = on ]; then
        idx=$(profile headset-head-unit)
        [ -n "$idx" ] || idx=$(profile headset-head-unit-cvsd)
        wpctl set-profile "$card" "$idx"
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          src=$(pw-dump | jq -r 'first(.[] | select(.type == "PipeWire:Interface:Node"
            and .info.props["media.class"] == "Audio/Source"
            and ((.info.props["node.name"] // "") | startswith("bluez_input"))) | .id) // empty')
          [ -n "$src" ] && break
          sleep 0.3
        done
        [ -n "''${src:-}" ] && wpctl set-default "$src"
        notify-send -a 耳机 "耳机麦克风已开启" "通话模式：单声道 16 kHz，用完再按一次恢复高音质"
      else
        wpctl set-profile "$card" "$(profile a2dp-sink)"
        notify-send -a 耳机 "已恢复高音质" "A2DP 立体声，耳机麦克风关闭"
      fi
    '';
  };
in
{
  environment.systemPackages = [ headsetMic ];

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
      # Headset mics stay available through `headset-mic` (Super+Shift+N).
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
