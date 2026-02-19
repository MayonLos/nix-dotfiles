{ config, pkgs, ... }:

let
  # 使用 writeShellScript 定义脚本内容
  screenshotScript = pkgs.writeShellScript "screenshot.sh" ''
    set -euo pipefail

    # 显式指定依赖路径，防止系统环境缺少 maim 或 xclip
    PATH="$PATH:${pkgs.lib.makeBinPath [ pkgs.maim pkgs.xclip pkgs.libnotify pkgs.coreutils ]}"

    BASE_DIR="$HOME/Pictures/Screenshots"
    DATE_FORMAT="%Y-%m-%d"
    TIME_FORMAT="%H%M%S"

    setup_directory() {
      local today
      today="$(date +"$DATE_FORMAT")"
      SAVE_DIR="$BASE_DIR/$today"
      mkdir -p "$SAVE_DIR"
    }

    generate_filename() {
      local timestamp
      timestamp="$(date +"$TIME_FORMAT")"
      FILE="$SAVE_DIR/screenshot_''${timestamp}.png" # 注意：Nix 字符串中 $ 需要双写转义
    }

    cleanup() {
      if [[ -f $FILE && ! -s $FILE ]]; then
        rm -f "$FILE"
      fi
    }

    take_screenshot() {
      if maim -s -u -m 10 "$FILE" 2>/dev/null; then
        xclip -selection clipboard -t image/png -i "$FILE" &
        
        local rel_path="''${FILE#$HOME/}"
        
        notify-send -u low "📸 截图完成" \
          "保存: ~/$rel_path\n已复制到剪贴板"
        
        return 0
      else
        return 1
      fi
    }

    # Main logic
    setup_directory
    generate_filename
    trap cleanup EXIT
    take_screenshot
  '';
in
{
  # 将脚本写入到 ~/.local/bin
  home.file.".local/bin/screenshot.sh" = {
    source = screenshotScript;
    executable = true;
  };

  # 确保依赖包已安装
  home.packages = with pkgs; [
    maim
    xclip
    libnotify
  ];

  home.sessionPath = [ "$HOME/.local/bin" ];
}