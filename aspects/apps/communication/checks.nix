{ pkgs, home, ... }:
let
  thunderbird = home.programs.thunderbird.package;
  wechat = pkgs.lib.findFirst (
    package: (package.name or "") == "wechat-with-fcitx-ibus"
  ) (throw "communication: selected home.packages lacks the WeChat IME wrapper") home.home.packages;
in
{
  communication-portal-config = pkgs.runCommand "communication-portal-config-check" { } ''
    grep -Fq 'widget.use-xdg-desktop-portal.file-picker", 1' \
      ${thunderbird}/lib/thunderbird/mozilla.cfg
    touch "$out"
  '';
  communication-wechat-ime = pkgs.runCommand "communication-wechat-ime-check" { } ''
    # Execute the selected launcher's actual shell logic with only its final
    # application target replaced, so checks never start or log into WeChat.
    cat > probe <<'PROBE'
    #!${pkgs.runtimeShell}
    printf '%s\n' "$QT_QPA_PLATFORM" "$QT_IM_MODULE" "$IBUS_USE_PORTAL" "$#" "$@"
    PROBE
    chmod +x probe
    substitute ${wechat}/bin/wechat launcher \
      --replace-fail '${pkgs.unstable.wechat}/bin/wechat' "$PWD/probe"
    chmod +x launcher
    QT_QPA_PLATFORM=wayland QT_IM_MODULE=fcitx IBUS_USE_PORTAL=0 \
      ./launcher 'weixin://example?a=1&b=2' 'argument with spaces' "" > actual
    printf '%s\n' xcb ibus 1 3 'weixin://example?a=1&b=2' 'argument with spaces' "" > expected
    cmp expected actual
    ./launcher > actual-empty
    printf '%s\n' xcb ibus 1 0 > expected-empty
    cmp expected-empty actual-empty

    # Comparing the full file also protects icons, MIME/URL handlers, field
    # codes and translated metadata when the underlying package changes.
    substitute ${pkgs.unstable.wechat}/share/applications/wechat.desktop expected.desktop \
      --replace-fail 'Exec=wechat ' 'Exec=${wechat}/bin/wechat '
    cmp expected.desktop ${wechat}/share/applications/wechat.desktop
    grep -Fxq 'Exec=${wechat}/bin/wechat %U' ${wechat}/share/applications/wechat.desktop
    test -d ${wechat}/share/icons
    touch "$out"
  '';
}
