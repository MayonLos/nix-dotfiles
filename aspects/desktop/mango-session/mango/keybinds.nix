{
  lib,
  pkgs,
  display,
}:
let
  defaultBinds = [
    # Expand only after helpText is rendered, so its own path is not recursive.
    "SUPER,F1,spawn,__MANGO_HELP__"
    "SUPER,E,spawn,workspace-files"
    "SUPER,B,spawn,workspace-browser"
    "SUPER,Return,spawn,workspace-terminal"
    "SUPER+ALT,H,spawn,herdr-terminal"
    # A unique app id distinguishes each tool from ordinary Kitty windows.
    # Title argument "none" means match by app id only.
    "SUPER+SHIFT,Return,toggle_named_scratchpad,mayon-scratch,none,${lib.getExe pkgs.kitty} --class=mayon-scratch"
    "SUPER+ALT,E,toggle_named_scratchpad,mayon-files,none,${lib.getExe pkgs.kitty} --class=mayon-files ${lib.getExe pkgs.yazi}"
    "SUPER+ALT,M,toggle_named_scratchpad,mayon-monitor,none,${lib.getExe pkgs.kitty} --class=mayon-monitor btop"
    "SUPER+ALT,C,toggle_named_scratchpad,mayon-clash,none,${lib.getExe pkgs.kitty} --class=mayon-clash clashtui-mayon"
    "SUPER+CTRL,G,toggleglobal"
    "SUPER+ALT,G,toggleoverlay"
    "SUPER+CTRL,S,tag_special_silent"
    "ALT,space,spawn,noctalia msg panel-toggle launcher"
    "SUPER,A,spawn,noctalia msg plugin nix-dotfiles/launchpad:control all toggle"
    "SUPER+ALT,D,spawn,noctalia msg notification-dnd-toggle"
    "SUPER+ALT,I,spawn,noctalia msg caffeine-toggle"
    "SUPER,S,spawn,noctalia msg panel-toggle control-center"
    # No argument: the keybind path has no client, so this toggles tag 0
    # on the selected monitor.
    "SUPER+SHIFT,S,toggle_special_tag"
    "SUPER+ALT,L,spawn,noctalia msg session lock"
    "SUPER,0,toggleoverview"
    "SUPER+SHIFT,0,togglejump"

    "SUPER,H,focusdir,left"
    "SUPER,Left,focusdir,left"
    "SUPER,J,focusdir,down"
    "SUPER,Down,focusdir,down"
    "SUPER,K,focusdir,up"
    "SUPER,Up,focusdir,up"
    "SUPER,L,focusdir,right"
    "SUPER,Right,focusdir,right"

    "SUPER+SHIFT,H,move_client,left"
    "SUPER+SHIFT,Left,move_client,left"
    "SUPER+SHIFT,J,move_client,down"
    "SUPER+SHIFT,Down,move_client,down"
    "SUPER+SHIFT,K,move_client,up"
    "SUPER+SHIFT,Up,move_client,up"
    "SUPER+SHIFT,L,move_client,right"
    "SUPER+SHIFT,Right,move_client,right"

    # Directions only. parse_monitor_arg accepts left/right/up/down.
    # HJKL is not bound: those chords used to be exchange_client.
    "SUPER+CTRL,Left,tagmon,left"
    "SUPER+CTRL,Down,tagmon,down"
    "SUPER+CTRL,Up,tagmon,up"
    "SUPER+CTRL,Right,tagmon,right"

    "SUPER,Page_Down,viewtoright"
    "SUPER,U,viewtoright"
    "SUPER,Page_Up,viewtoleft"
    "SUPER,I,viewtoleft"
    "SUPER+ALT,J,overcircle,current_prev"
    "SUPER+ALT,K,overcircle,current_next"
    "SUPER+CTRL,Page_Down,tagtoright"
    "SUPER+CTRL,U,tagtoright"
    "SUPER+CTRL,Page_Up,tagtoleft"
    "SUPER+CTRL,I,tagtoleft"
    # niri had two distinct pairs here -- move-column-to-workspace and
    # move-workspace -- and mango has only the first, so the Shift pair was
    # a byte-identical duplicate of the Ctrl pair above. Reused for the one
    # dwm knob the layout has and nothing else could reach: nmaster.
    "SUPER+SHIFT,I,incnmaster,1"
    "SUPER+SHIFT,U,incnmaster,-1"

    "SUPER,1,view,1"
    "SUPER,2,view,2"
    "SUPER,3,view,3"
    "SUPER,4,view,4"
    "SUPER,5,view,5"
    "SUPER,6,view,6"
    "SUPER,7,view,7"
    "SUPER,8,view,8"
    "SUPER,9,view,9"
    # tag follows, tagsilent does not: tag_client() calls
    # client_switch_view() and then focuses the moved window
    # (src/manage/client.c), while tag_silent() only rewrites c->tags.
    # Shift gets the one that follows because that is the reflex; Ctrl
    # keeps the stay-put variant for parking a window out of the way.
    "SUPER+CTRL,1,tagsilent,1"
    "SUPER+CTRL,2,tagsilent,2"
    "SUPER+CTRL,3,tagsilent,3"
    "SUPER+CTRL,4,tagsilent,4"
    "SUPER+CTRL,5,tagsilent,5"
    "SUPER+CTRL,6,tagsilent,6"
    "SUPER+CTRL,7,tagsilent,7"
    "SUPER+CTRL,8,tagsilent,8"
    "SUPER+CTRL,9,tagsilent,9"
    "SUPER+SHIFT,1,tag,1"
    "SUPER+SHIFT,2,tag,2"
    "SUPER+SHIFT,3,tag,3"
    "SUPER+SHIFT,4,tag,4"
    "SUPER+SHIFT,5,tag,5"
    "SUPER+SHIFT,6,tag,6"
    "SUPER+SHIFT,7,tag,7"
    "SUPER+SHIFT,8,tag,8"
    "SUPER+SHIFT,9,tag,9"

    # setmfact keeps dwm's convention (src/dispatch/bind.c, set_master_factor):
    # an argument below 1.0 is a *delta* applied to the current mfact, and
    # only >= 1.0 is absolute, taken as value - 1.0. So the two absolute
    # binds below read 1.55 and 1.9, not 0.55 and 0.9 -- written the obvious
    # way they are deltas that overshoot the 0.9 guard and silently do
    # nothing at all.
    "SUPER,Home,focusstack,prev"
    "SUPER,End,focusstack,next"
    "SUPER,Tab,focuslast"
    # Super+R enters resize. The scroller width cycle moved to
    # Super+Shift+R and still returns immediately outside scroller.
    "SUPER,R,setkeymode,resize"
    "SUPER+CTRL,R,setmfact,1.55"
    "SUPER,F,togglemaximizescreen"
    "SUPER+SHIFT,F,togglefullscreen"
    "SUPER+CTRL,F,setmfact,1.9"
    "SUPER,C,centerwin"
    "SUPER,Minus,setmfact,-0.05"
    "SUPER,Equal,setmfact,+0.05"
    # Unsigned 0 is a target size on a floating window. +0 is a zero delta
    # on both tiled and floating windows, so the other axis stays put.
    "SUPER+SHIFT,Minus,resizewin,+0,-10"
    "SUPER+SHIFT,Equal,resizewin,+0,+10"
    "SUPER,space,togglefloating"
    "SUPER,W,switch_layout"
    "SUPER,Z,zoom"
    "SUPER+SHIFT,G,togglegaps"

    "NONE,Print,spawn,mark-shot"
    "CTRL,Print,spawn,screenshot-screen"
    "SHIFT,Print,spawn,wayscrollshot"
    # Screen-text OCR, so the whole Print family is capture: bare = region
    # screenshot, Ctrl = copy current screen, Shift = scrolling capture,
    # Super = OCR the selection,
    # Super+Shift = OCR the entire desktop. Scripts come from
    # programs/apps/screenshot.nix.
    "SUPER,Print,spawn,ocr-region"
    "SUPER+SHIFT,Print,spawn,ocr-screen"
    "CTRL+ALT,Delete,spawn,noctalia msg panel-toggle session"
    "SUPER,V,spawn,noctalia msg panel-toggle clipboard"
    "SUPER+SHIFT,P,sleep_monitor,${display.name}"
    "SUPER+SHIFT,O,wakeup_monitor,${display.name}"
    "SUPER+SHIFT,W,spawn,noctalia msg wallpaper-random"
    "SUPER+SHIFT,A,spawn,noctalia msg caffeine-toggle"

    "SUPER+SHIFT,R,switch_proportion_preset"
    # These two are a pair. `toggle_scratchpad` only ever acts on a client
    # whose `is_in_scratchpad` flag is set, and mango sets that flag only
    # inside `set_minimized()` (src/manage/client.c) -- so without a
    # minimize bind the toggle is a permanent no-op. It was: dispatching it
    # by hand returned `{"success":true}` and changed nothing.
    "SUPER+SHIFT,grave,minimized"
    "SUPER,grave,toggle_scratchpad"
    "SUPER+ALT,T,switcher,next"

  ];
  commonBinds = [
    # mango hot-reloads config.conf; without a bind there is no way to ask
    # for it after editing the file by hand.
    "SUPER+ALT,R,reload_config"
    "SUPER,Q,killclient"
    # The safety net: reachable from any mode, including one this config no
    # longer defines. Not `NONE,Escape` -- see point 3 above.
    "SUPER,Escape,setkeymode,default"

  ];
  hardwareBinds = [
    "NONE,XF86AudioRaiseVolume,spawn,noctalia msg volume-up"
    "NONE,XF86AudioLowerVolume,spawn,noctalia msg volume-down"
    "NONE,XF86AudioMute,spawn,noctalia msg volume-mute"
    "NONE,XF86AudioMicMute,spawn,noctalia msg mic-mute"
    "NONE,XF86MonBrightnessUp,spawn,noctalia msg brightness-up"
    "NONE,XF86MonBrightnessDown,spawn,noctalia msg brightness-down"
    "NONE,XF86AudioPlay,spawn,playerctl play-pause"
    "NONE,XF86AudioStop,spawn,playerctl stop"
    "NONE,XF86AudioPrev,spawn,playerctl previous"
    "NONE,XF86AudioNext,spawn,playerctl next"

  ];
  resizeBinds = [
    "NONE,H,resizewin,-10,+0"
    "NONE,Left,resizewin,-10,+0"
    "NONE,J,resizewin,+0,+10"
    "NONE,Down,resizewin,+0,+10"
    "NONE,K,resizewin,+0,-10"
    "NONE,Up,resizewin,+0,-10"
    "NONE,L,resizewin,+10,+0"
    "NONE,Right,resizewin,+10,+0"
    "NONE,Escape,setkeymode,default"

  ];
  gestures = [
    "none,left,4,viewnext_have_client"
    "none,right,4,viewprev_have_client"
    "none,up,4,toggleoverview"
    "none,down,4,toggleoverview"
    "none,up,3,focusdir,up"
    "none,down,3,focusdir,down"
    "none,left,3,focusdir,left"
    "none,right,3,focusdir,right"

  ];
  allKeyRows = defaultBinds ++ commonBinds ++ hardwareBinds ++ resizeBinds;
  helpKeyRows = lib.filter (row: !(lib.hasInfix "__MANGO_HELP__" row)) allKeyRows;
  actionNames = {
    spawn = "启动";
    focusdir = "按方向聚焦窗口";
    move_client = "按方向移动窗口";
    tagmon = "移动窗口到相邻显示器";
    viewtoright = "下一个占用工作区";
    viewtoleft = "上一个占用工作区";
    overcircle = "切换同工作区窗口";
    tagtoright = "将窗口移到右侧工作区";
    tagtoleft = "将窗口移到左侧工作区";
    view = "切换到工作区";
    tagsilent = "移到工作区但留在当前页";
    tag = "移到工作区并跟随";
    focusstack = "切换窗口";
    focuslast = "返回上个窗口";
    switcher = "切换器";
    toggleoverview = "切换概览";
    togglejump = "切换跳转标签";
    toggle_special_tag = "切换特殊工作区";
    setkeymode = "进入或退出按键模式";
    incnmaster = "调整主窗口数量";
    setmfact = "调整主区域比例";
    togglemaximizescreen = "切换最大化";
    togglefullscreen = "切换全屏";
    centerwin = "居中窗口";
    resizewin = "调整窗口大小";
    togglefloating = "切换浮动";
    switch_layout = "切换布局";
    zoom = "交换主窗口";
    togglegaps = "切换窗口间距";
    switch_proportion_preset = "切换滚动布局比例";
    minimized = "最小化窗口";
    toggle_scratchpad = "找回最小化窗口";
    toggle_named_scratchpad = "呼出或隐藏命名工具";
    toggleglobal = "切换跨工作区可见";
    toggleoverlay = "切换窗口置顶";
    tag_special_silent = "移入或取回特殊工作区窗口";
    sleep_monitor = "关闭显示器";
    wakeup_monitor = "唤醒显示器";
    reload_config = "重载配置";
    killclient = "关闭窗口";
  };
  keyRow =
    row:
    let
      # This is display-only text. Splitting a store-backed command otherwise
      # carries its Nix string context into action/app-id attribute lookups.
      # The real bindings above retain their executable dependencies.
      fields = lib.splitString "," (builtins.unsafeDiscardStringContext row);
      key = lib.concatStringsSep "," (lib.take 2 fields);
      action = lib.elemAt fields 2;
      label = actionNames.${action} or action;
      scratchpadNames = {
        mayon-scratch = "临时终端";
        mayon-files = "临时文件 Yazi";
        mayon-monitor = "系统监视 btop";
        mayon-clash = "Clash 代理";
      };
      args =
        if action == "toggle_named_scratchpad" then
          scratchpadNames.${lib.elemAt fields 3} or (lib.elemAt fields 3)
        else
          lib.concatStringsSep "," (lib.drop 3 fields);
    in
    if
      builtins.elem action [
        "3"
        "4"
      ]
    then
      "${lib.elemAt fields 2}-finger ${lib.elemAt fields 1} → ${
        actionNames.${lib.elemAt fields 3} or (lib.elemAt fields 3)
      } ${lib.concatStringsSep "," (lib.drop 4 fields)}"
    else
      "${key} → ${label}${lib.optionalString (args != "") ": ${args}"}";
  categories = [
    {
      title = "启动器与会话";
      rows = lib.filter (row: lib.hasInfix ",spawn," row) helpKeyRows;
    }
    {
      title = "窗口与工作区";
      rows = lib.filter (
        row:
        builtins.elem (lib.elemAt (lib.splitString "," row) 2) [
          "focusdir"
          "move_client"
          "tagmon"
          "viewtoright"
          "viewtoleft"
          "overcircle"
          "tagtoright"
          "tagtoleft"
          "view"
          "tagsilent"
          "tag"
          "focusstack"
          "focuslast"
          "switcher"
          "toggleoverview"
          "togglejump"
          "toggle_special_tag"
          "tag_special_silent"
        ]
      ) helpKeyRows;
    }
    {
      title = "布局与窗口状态";
      rows = lib.filter (
        row:
        builtins.elem (lib.elemAt (lib.splitString "," row) 2) [
          "setkeymode"
          "incnmaster"
          "setmfact"
          "togglemaximizescreen"
          "togglefullscreen"
          "centerwin"
          "resizewin"
          "togglefloating"
          "toggleglobal"
          "toggleoverlay"
          "switch_layout"
          "zoom"
          "togglegaps"
          "switch_proportion_preset"
          "minimized"
          "toggle_scratchpad"
          "toggle_named_scratchpad"
          "sleep_monitor"
          "wakeup_monitor"
        ]
      ) defaultBinds;
    }
    {
      title = "所有模式均可用";
      rows = commonBinds ++ hardwareBinds;
    }
    {
      title = "调整大小模式";
      rows = resizeBinds;
    }
    {
      title = "触控板手势";
      rows = gestures;
    }
  ];
  helpText = lib.concatStringsSep "\n\n" (
    map (
      category: "${category.title}\n${lib.concatStringsSep "\n" (map keyRow category.rows)}"
    ) categories
  );
in
{
  inherit
    defaultBinds
    commonBinds
    hardwareBinds
    resizeBinds
    gestures
    helpText
    ;
}
