{
    pkgs,
    ...
}:

{
  programs.firefox = {
    enable = true;

    profiles.default = {
      id = 0;
      name = "default";

      userChrome = ''
  /* 隐藏整个 TabsToolbar */
  #TabsToolbar {
    visibility: collapse !important;
  }

  /* 隐藏右上角窗口控制按钮 */
  .titlebar-buttonbox-container {
    display: none !important;
  }

  /* 移除标题栏高度 */
  #titlebar {
    margin-bottom: -45px !important;
  }

  /* 让导航栏贴顶 */
  #nav-bar {
    margin-top: -2px !important;
  }
'';

    };
  };
}
