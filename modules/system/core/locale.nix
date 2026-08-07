_: {
  time.timeZone = "Asia/Shanghai";

  i18n = {
    # Was implicit before (this is also the NixOS default) — stated explicitly so
    # the file matches its name and the choice is visible.
    defaultLocale = "en_US.UTF-8";

    # zh_CN is built even though the session runs in English, so applications that
    # ask for it (and `LANG=zh_CN.UTF-8 <cmd>` one-offs) find a real locale instead
    # of falling back to C.
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "zh_CN.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
  };

  system.stateVersion = "25.11";
}
