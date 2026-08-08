{ pkgs, config, ... }:
{
  # Qt 应用（mark-shot、virt-manager 的对话框等）此前不跟主题：文件保存框是
  # 一片浅灰的 Fusion 默认样式。
  #
  # 原因是配置只做了一半：niri 的 environment 里设了 QT_QPA_PLATFORMTHEME=qt6ct，
  # noctalia 的 qt 模板也把配色渲染到了 ~/.config/qt6ct/colors/noctalia.conf，
  # 但 qt6ct 自己的主配置 qt6ct.conf 从来没人写过 —— 没有它，qt6ct 不知道该用
  # 哪套配色，于是回落到默认浅色。
  #
  # 这个文件是可变的（qt6ct 的 GUI 也会写它），所以用 activation 播种而不是
  # home.file 软链：只在缺失时创建，之后你在 qt6ct 里怎么调都不会被覆盖。
  home.activation.seedQt6ctConfig =
    let
      colorScheme = "${config.home.homeDirectory}/.config/qt6ct/colors/noctalia.conf";
      conf = pkgs.writeText "qt6ct.conf" ''
        [Appearance]
        color_scheme_path=${colorScheme}
        custom_palette=true
        icon_theme=Papirus-Dark
        standard_dialogs=default
        style=Fusion
      '';
    in
    config.lib.dag.entryAfter [ "writeBoundary" ] ''
      target="${config.home.homeDirectory}/.config/qt6ct/qt6ct.conf"
      if [ ! -e "$target" ]; then
        run mkdir -p "$(dirname "$target")"
        run ${pkgs.coreutils}/bin/install -m 0644 ${conf} "$target"
      fi
    '';
}
