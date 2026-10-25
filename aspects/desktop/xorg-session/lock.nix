{ palette }:
{
  pkgs,
  lib,
  ...
}:
let
  rgba = color: alpha: "${lib.removePrefix "#" color}${alpha}";
  i3lockColor = pkgs.i3lock-color.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./resources/i3lock-gradient.patch ];
    postPatch = (old.postPatch or "") + ''
      grep -q 'xorg-dwm-idle-ring-gradient-v1' unlock_indicator.c || {
        echo "Xorg idle ring gradient patch did not apply" >&2
        exit 1
      }
    '';
  });
  defaultWallpaper =
    (import ../../appearance/appearance/resources/wallpaper/package.nix { inherit pkgs palette; })
    .default;
  lock = pkgs.writeShellApplication {
    name = "xorg-lock";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.imagemagick
    ];
    text = ''
      # Home's wallpaper loop records its active image here. Accept one absolute,
      # readable regular-file path; a missing or stale record falls back to the
      # public default wallpaper. The local image and its darkened cache stay
      # under the user's cache directory and never enter the Nix store.
      wallpaper=${defaultWallpaper}
      record="''${XDG_RUNTIME_DIR:-}/nix-dotfiles-xorg/wallpaper"
      if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -f "$record" ] \
        && IFS= read -r candidate < "$record" \
        && [[ "$candidate" = /* ]] && [ -f "$candidate" ] && [ -r "$candidate" ]; then
        wallpaper="$candidate"
      fi

      umask 077
      cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/nix-dotfiles/xorg-lock"
      mkdir -p "$cache_dir"
      chmod 700 "$cache_dir"

      prepare_background() {
        local source="$1" metadata key output temporary
        metadata="$(stat --format='%Y:%s:%i' -- "$source")"
        key="$(printf '%s\0%s' "$source" "$metadata" | sha256sum | cut -d ' ' -f 1)"
        output="$cache_dir/$key.png"
        if [ ! -s "$output" ]; then
          temporary="$cache_dir/.$key.$$.tmp.png"
          trap 'rm -f -- "$temporary"' EXIT
          if ! magick "$source" -auto-orient \
            -fill '${palette.black}' -colorize 48% -strip "PNG24:$temporary"; then
            rm -f -- "$temporary"
            trap - EXIT
            return 1
          fi
          chmod 600 "$temporary"
          mv -f -- "$temporary" "$output"
          trap - EXIT
        fi
        printf '%s\n' "$output"
      }

      if ! background="$(prepare_background "$wallpaper")"; then
        background="$(prepare_background ${defaultWallpaper})"
      fi

      # i3lock-color 2.13.c.5 closes XSS_SLEEP_LOCK_FD after MapNotify.
      # exec and --nofork preserve xss-lock's process/inhibitor ownership.
      # i3lock-color scales the indicator and text canvas by output DPI itself;
      # these sizes and positions therefore stay in logical coordinates.
      unset LC_ALL
      export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
      export LC_TIME=zh_CN.UTF-8
      exec ${lib.getExe i3lockColor} \
        --nofork --ignore-empty-password --show-failed-attempts \
        --color=${rgba palette.black "ff"} --image="$background" --fill \
        --clock --force-clock --indicator --refresh-rate=5 \
        --radius=96 --ring-width=3 \
        --inside-color=${rgba palette.deep "c8"} \
        --ring-color=${rgba palette.blue "ff"} \
        --line-color=${rgba palette.black "00"} --separator-color=${rgba palette.black "00"} \
        --insidever-color=${rgba palette.deep "e8"} \
        --ringver-color=${rgba palette.cyan "ff"} \
        --insidewrong-color=${rgba palette.deep "e8"} \
        --ringwrong-color=${rgba palette.red "ff"} \
        --keyhl-color=${rgba palette.blue "ff"} \
        --bshl-color=${rgba palette.orange "ff"} \
        --verif-color=${rgba palette.cyan "ff"} \
        --wrong-color=${rgba palette.red "ff"} \
        --time-color=${rgba palette.brightFg "ff"} \
        --date-color=${rgba palette.muted "ff"} \
        --layout-color=${rgba palette.fg "ff"} \
        --modif-color=${rgba palette.orange "ff"} \
        --greeter-color=${rgba palette.muted "ff"} \
        --time-font=${lib.escapeShellArg palette.fonts.mono} \
        --date-font=${lib.escapeShellArg palette.fonts.mono} \
        --verif-font=${lib.escapeShellArg palette.fonts.mono} \
        --wrong-font=${lib.escapeShellArg palette.fonts.mono} \
        --layout-font=${lib.escapeShellArg palette.fonts.mono} \
        --greeter-font=${lib.escapeShellArg palette.fonts.mono} \
        --time-size=40 --date-size=12 --verif-size=11 --wrong-size=11 \
        --layout-size=11 --modif-size=11 --greeter-size=11 \
        --time-str='%H:%M' --date-str='%m月%d日 周%a' \
        --ind-pos='x+w/2:y+h/2' \
        --time-align=0 --date-align=0 --verif-align=0 --wrong-align=0 --greeter-align=0 \
        --time-pos='ix:iy+14' --date-pos='ix:iy+41' \
        --verif-pos='ix:iy+112' --wrong-pos='ix:iy+112' \
        --layout-pos='ix:iy+154' --modif-pos='ix:iy+174' \
        --greeter-pos='ix:iy+140' --greeter-text='输入密码解锁' \
        --keylayout=1 --verif-text='验证中' --wrong-text='密码错误' \
        --noinput-text='请输入密码' --lock-text='已锁定' --lockfailed-text='锁定失败'
    '';
  };
in
{
  # Successful PAM authentication immediately unlocks in upstream i3lock-color;
  # Blue is the idle ring, cyan the verification ring, red means failure.
  home.packages = [ lock ];
}
