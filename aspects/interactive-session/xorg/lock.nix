{ palette }:
{ pkgs, lib, ... }:
let
  rgba = color: alpha: "${lib.removePrefix "#" color}${alpha}";
  # Only this public repository image enters the store. Prepare the subdued
  # backdrop at build time, so locking never waits for a screenshot or filter.
  background =
    pkgs.runCommand "xorg-lock-background.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        magick ${../resources/wallpaper/wallpaper-005.png} \
          -fill '${palette.bg}' -colorize 28% -strip PNG24:"$out"
      '';
  lock = pkgs.writeShellApplication {
    name = "xorg-lock";
    text = ''
      # i3lock-color 2.13.c.5 closes XSS_SLEEP_LOCK_FD after MapNotify.
      # exec and --nofork preserve xss-lock's process/inhibitor ownership.
      # Xft.dpi is handled by the locker itself, including these logical sizes.
      exec ${lib.getExe pkgs.i3lock-color} \
        --nofork --ignore-empty-password --show-failed-attempts \
        --color=${rgba palette.bg "ff"} --image=${background} --fill \
        --clock --force-clock --indicator --refresh-rate=5 \
        --radius=28 --ring-width=2 \
        --inside-color=${rgba palette.bg "b8"} \
        --ring-color=${rgba palette.selection "cc"} \
        --line-color=00000000 --separator-color=00000000 \
        --insidever-color=${rgba palette.bg "e6"} \
        --ringver-color=${rgba palette.blue "ff"} \
        --insidewrong-color=${rgba palette.bg "e6"} \
        --ringwrong-color=${rgba palette.red "ff"} \
        --keyhl-color=${rgba palette.blue "ff"} \
        --bshl-color=${rgba palette.orange "ff"} \
        --verif-color=${rgba palette.blue "ff"} \
        --wrong-color=${rgba palette.red "ff"} \
        --time-color=${rgba palette.brightFg "ff"} \
        --date-color=${rgba palette.fg "ff"} \
        --layout-color=${rgba palette.fg "ff"} \
        --modif-color=${rgba palette.orange "ff"} \
        --greeter-color=${rgba palette.muted "ff"} \
        --time-font=${lib.escapeShellArg palette.fonts.mono} \
        --date-font=${lib.escapeShellArg palette.fonts.sans} \
        --verif-font=${lib.escapeShellArg palette.fonts.sans} \
        --wrong-font=${lib.escapeShellArg palette.fonts.sans} \
        --layout-font=${lib.escapeShellArg palette.fonts.mono} \
        --greeter-font=${lib.escapeShellArg palette.fonts.sans} \
        --time-size=56 --date-size=12 --verif-size=11 --wrong-size=11 \
        --layout-size=11 --modif-size=11 --greeter-size=11 \
        --time-str='%H:%M' --date-str='%Y-%m-%d · %A' \
        --ind-pos='x+w/2:y+h/2+32' \
        --time-pos='ix:iy-120' --date-pos='tx:ty+28' \
        --verif-pos='ix:iy+5' --wrong-pos='ix:iy+5' \
        --layout-pos='ix:iy+58' --modif-pos='ix:iy+80' \
        --greeter-pos='ix:iy+108' --greeter-text='输入密码解锁' \
        --keylayout=1 --verif-text='验证中' --wrong-text='请重试' \
        --noinput-text='请输入' --lock-text='已锁定' --lockfailed-text='锁定失败'
    '';
  };
in
{
  # Successful PAM authentication immediately unlocks in upstream i3lock-color;
  # Blue marks input/verifying and red marks failure; idle stays subdued.
  home.packages = [ lock ];
}
