{ pkgs, ... }:

{
    programs.foot = {
        enable = true;
        package = pkgs.foot;
        settings = {
            main = {
                term = "xterm-256color";
                font = "JetBrainsMono Nerd Font:size=8";
                dpi-aware = true;
            };
            mouse = {
                hide-when-typing = true;
                alternate-scroll-mode = true;
            };
            tweak = {
                font-monospace-warn = false;
            };
        };
    };
}