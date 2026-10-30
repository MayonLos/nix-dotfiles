{ pkgs, ... }:
let
  # Feature fixture: it is deliberately not a deployable host or a new package set.
  fixture = (import ./default.nix { }).den.aspects.voice-input.homeManager {
    inherit pkgs;
    config.nixDotfiles.graphicalSessionTargets = [ "voice-fixture.target" ];
  };
  service = fixture.systemd.user.services.mayon-voice;
  socket = fixture.systemd.user.sockets.mayon-voice;
in
assert !(service ? Install);
assert service.Unit.PartOf == [ "voice-fixture.target" ];
assert socket.Install.WantedBy == [ "voice-fixture.target" ];
assert socket.Socket.ListenStream == "%t/mayon-voice/control.sock";
assert socket.Socket.SocketMode == "0600";
assert socket.Socket.DirectoryMode == "0700";
assert service.Service.KillMode == "control-group";
assert fixture.i18n.inputMethod.fcitx5.addons == [ pkgs.mayonVoice.fcitxAddon ];
{
  mayon-voice = pkgs.mayonVoice;
  mayon-voice-fcitx = pkgs.mayonVoice.fcitxAddon;
}
