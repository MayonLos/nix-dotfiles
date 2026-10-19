{ config, pkgs, ... }:
{
  xdg.desktopEntries.workspace-task-terminal = {
    name = "长任务终端";
    comment = "在终端关闭前持有睡眠抑制；不会禁止自动锁屏";
    exec = "${pkgs.kitty}/bin/kitty --title 长任务终端 ${config.home.profileDirectory}/bin/workspace-task ${pkgs.zsh}/bin/zsh -i";
    icon = "utilities-terminal";
    terminal = false;
    categories = [
      "System"
      "TerminalEmulator"
    ];
  };
  home.packages = with pkgs; [
    qt6Packages.qt6ct
    xclip
    brightnessctl
    ddcutil
    playerctl
  ];
}
