{ pkgs, ... }:

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # 为 Steam 流式传输开放端口
    dedicatedServer.openFirewall = true; # 为私服开放端口
    localNetworkGameTransfers.openFirewall = true; # 局域网游戏传输
    gamescopeSession.enable = true; # 允许在登录界面进入类似 Steam Deck 的模式
  };
}