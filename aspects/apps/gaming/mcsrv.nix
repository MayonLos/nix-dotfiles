{ pkgs, ... }:
let
  java = import ../../../lib/java.nix { inherit pkgs; };
  javaMap = builtins.mapAttrs (_: jdk: "${jdk}/bin/java") java.jdks;
in
{
  home.packages = [
    pkgs.mcsrvMayon
    pkgs.restic
    pkgs.tailscale
  ];
  home.sessionVariables.MCSRV_JAVA_MAP = builtins.toJSON javaMap;
  systemd.user.sessionVariables.MCSRV_JAVA_MAP = builtins.toJSON javaMap;
  xdg.desktopEntries.mcsrv-mayon = {
    name = "Minecraft 服务器管家";
    comment = "管理本地 Minecraft 服务端、玩家、模组与存档备份";
    exec = "${pkgs.kitty}/bin/kitty --class mcsrv-mayon --title Minecraft ${pkgs.mcsrvMayon}/bin/mcsrv-mayon";
    terminal = false;
    icon = "network-server";
    categories = [
      "Game"
      "Utility"
    ];
  };
}
