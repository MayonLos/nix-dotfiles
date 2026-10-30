# Private rule table. Locked Mango 0.18.3: option_defs.c / client_apply_rules().
# Later matches override properties; app_id AND title must match. Titles are
# matched at map time, NOT on later title changes. No Hyprland-only fields here.
{
  lib,
  assignAppTags ? false,
}:
let
  float = "is_floating:1";
  # One centered scale per role; Mango centers floated clients when no offset
  # is supplied. client.c:1698/1702 multiplies ratios by the full logical output area.
  dialog = "${float},width:0.56,height:0.64";
  compact = "${float},width:0.42,height:0.42";
  tools = "${float},width:0.46,height:0.58";
  panel = "${float},width:0.68,height:0.78";
  workspace = "${float},width:0.78,height:0.78";
  silent = "is_open_silent:1,is_tag_silent:1";
  opaque = "focused_opacity:1.0,unfocused_opacity:1.0";
  browser = "[Ff]irefox|org[.]mozilla[.]firefox";
  steam = "[Ss]team|steamwebhelper";
  jetbrains = "jetbrains-.*";
  communicationGroups = [
    "QQ|qq|com[.]qq[.]QQ"
    "wechat|WeChat|weixin|com[.]tencent[.](WeChat|wechat)"
    "discord|Discord|vesktop|Vesktop"
    "wemeet|wemeetapp|TencentMeeting"
  ];
  # Keep each row below the parser's 255 UTF-8 byte value limit. App scoping
  # avoids floating a browser tab / terminal / document named "Settings".
  dialogApps = [
    browser
    "[Tt]hunderbird|org[.]mozilla[.]Thunderbird"
    "[Tt]hunar|org[.]xfce[.]Thunar"
    "code|Code|code-oss|VSCodium|codium"
    jetbrains
    "libreoffice.*|soffice"
    "Zotero|zotero|org[.]zotero[.]Zotero"
    "MATLAB.*|matlab.*|com[.]mathworks[.]MATLAB.*"
    "com[.]obsproject[.]Studio|obs|org[.]kde[.]kdenlive|kdenlive"
    "gimp.*|Gimp.*|org[.]gimp[.]GIMP|[Bb]lender"
    "obsidian|md[.]obsidian[.]Obsidian|excalidraw|Excalidraw"
  ]
  ++ communicationGroups;
  forTitles =
    apps: actions: titles:
    builtins.concatMap (app: map (title: "${actions},app_id:^(${app})$,title:${title}") titles) apps;
  game = "^(steam_app_[0-9]+|Minecraft.*|minecraft.*|com[.]mojang[.]Minecraft.*|gamescope|Gamescope)$";
  rules = [
    # allow_tearing=2: opt normal clients out; only games opt in below.
    "force_tearing:0,no_blur:1,app_id:.*"
    # Kitty supplies its own translucent background; preserve native frost.
    "no_blur:0,app_id:^(kitty|Neovim|mayon-scratch|mayon-files|mayon-monitor|mayon-clash|mayon-tools|mayon-bili|mayon-docker-exec|mayon-herdr)$"

    # Native transients / X11 modal, splash, utility types already float.
    # These standalone portal windows have no reliable transient parent.
    "${dialog},app_id:^(xdg-desktop-portal-(gtk|gnome)|org[.]gtk[.]GtkFileChooserDialog)$"
    # Keep authentication prompts small while leaving their focus behavior native.
    "${compact},app_id:^(polkit-gnome-authentication-agent-1|lxqt-policykit-agent|org[.]kde[.]polkit-kde-authentication-agent-1|pinentry.*)$"
    "${panel},app_id:^dev[.]noctalia[.]Noctalia$"

    # Browser utility windows; Firefox's actual native app_id is "firefox".
    "${dialog},app_id:^(${browser})$,title:^(Library|Downloads|下载|我的足迹|资料库)$"
    "${compact},app_id:^(${browser})$,title:^(About (Mozilla )?Firefox|关于.*Firefox|Profile Missing)$"
    # No forced aspect rule exists in Mango. Retain the client's size/aspect
    # hints (no_size_hint remains unset); 480 x 270 is only the initial size.
    "${float},is_global:1,is_overlay:1,${silent},width:480,height:270,offset_x:96,offset_y:92,app_id:^(${browser})$,title:^(Picture-in-Picture|画中画)$"
    "${float},no_focus:1,${silent},app_id:^(${browser})$,title:^.*(Sharing Indicator|共享指示器)$"
    # Image viewers own one centered workspace-sized surface when launched.
    "${workspace},app_id:^(mpv|imv|swayimg|feh)$"
    "${opaque},app_id:^(mpv|imv|swayimg|feh|[Bb]lender|gimp.*|org[.]gimp[.]GIMP|com[.]obsproject[.]Studio|org[.]kde[.]kdenlive)$"

    # Standalone controls retain their application-scoped IDs from the existing table.
    "${tools},app_id:^(org[.]pulseaudio[.]pavucontrol|pavucontrol|[Bb]lueman-manager|org[.]blueman[.]Manager|[.]blueman-manager-wrapped|nm-connection-editor)$"
    "${tools},app_id:^(org[.]gnome[.]Calculator|qalculate-gtk|qalculate-qt|Qalculate-gtk|kcalc)$"
    "${tools},app_id:^(gcolor3|org[.]gnome[.]Gcolor3|org[.]kde[.]kcolorchooser|hyprpicker)$"
    "${dialog},app_id:^(qt[56]ct|fcitx5-config-qt|org[.]fcitx[.].*|org[.]fcitx[.]Fcitx5[.]Config)$"
    "${dialog},app_id:^(org[.]gnome[.]FileRoller|file-roller|kbd-layout-viewer5?|legion_gui)$"
    "${tools},app_id:^(com[.]github[.]hluk[.]copyq|copyq|CopyQ)$"
    # mark-shot capture and wayscrollshot selection are layer surfaces. Do not
    # resize their full-output capture areas; this only catches editor toplevels.
    "${float},no_animation:1,app_id:^(mark-shot|markshot|MarkShot)$"

    # Thunar: exact progress/preferences/bulk rename titles, main view tiled.
    "${compact},app_id:^([Tt]hunar|org[.]xfce[.]Thunar)$,title:^(Rename|重命名)"
    "${compact},app_id:^([Tt]hunar|org[.]xfce[.]Thunar)$,title:^(File Operation Progress|文件操作进度)$"
    "${dialog},app_id:^([Tt]hunar|org[.]xfce[.]Thunar)$,title:^(Bulk Rename.*|批量重命名.*|Thunar Preferences|Thunar 首选项|文件管理器首选项)$"
    "${dialog},app_id:^([Tt]hunar|org[.]xfce[.]Thunar)$,title:^.*( - Properties| Properties|属性)$"

    # Game launch transitions lose borders/shadows, but helpers are never
    # forced fullscreen. Fullscreen border/dim/shadow removal is native Mango.
    "no_blur:1,no_border:1,no_shadow:1,no_radius:1,no_animation:1,force_tearing:1,vrr_only_fullscreen:1,app_id:${game}"
    "${tools},app_id:^(${steam})$,title:^(Friends List|Steam - Friends|好友列表|好友与聊天)$"
    "${dialog},app_id:^(${steam})$,title:^(Steam Settings|Settings|Steam Login|Sign in to Steam|Steam 登录|设置)$"
    "${float},${silent},no_focus:1,no_animation:1,app_id:^(${steam})$,title:^(Notification|Steam Notification|通知)"
    "${dialog},app_id:^(org[.]prismlauncher[.]PrismLauncher|PrismLauncher|prismlauncher)$,title:^(Console|Minecraft Log|Edit Instance|Instance Settings|实例设置|控制台)(.*)$"

    "${dialog},app_id:^(org[.]prismlauncher[.]PrismLauncher|PrismLauncher|prismlauncher)$,title:^Prism Launcher Quick Setup(.*)$"

    # IDE startup / agreement and genuine tool windows, never all IDE windows.
    # JetBrains Wayland dialogs retain a fixed client buffer: forcing a larger
    # compositor size leaves a transparent frame. Keep their requested size.
    "${float},app_id:^(${jetbrains})$,title:^.*(User Agreement|License Activation|License Agreement)$"
    "${float},no_animation:1,app_id:^(${jetbrains})$,title:^(splash|Splash|win[0-9]+)$"
    "${compact},app_id:^(libreoffice.*|soffice)$,title:^(About LibreOffice|关于 LibreOffice|Welcome to LibreOffice[.])$"
    "${dialog},app_id:^(libreoffice.*|soffice)$,title:^(Database Wizard|数据库向导)$"
    "${dialog},app_id:^(Zotero|zotero)$,title:^(Zotero (LibreOffice Integration|Preferences|Settings)|Document Preferences)$"
    "${float},app_id:^(gimp.*|Gimp.*|org[.]gimp[.]GIMP)$,title:^(Toolbox|工具箱|.* - (Brushes|Layers|Tool Options))$"
    "${dialog},app_id:^(com[.]obsproject[.]Studio|obs)$,title:^(Auto-Configuration Wizard|自动配置向导)$"
    # Locked virt-manager ui/createconn.ui + createvm.ui; zh_CN catalogue.
    "${dialog},app_id:^(virt-manager|[.]virt-manager-wrapped)$,title:^(Add Connection|添加连接|New VM|新建虚拟机)$"
    # virtManager/host.py adds the connection name before the translated suffix.
    "${dialog},app_id:^(virt-manager|[.]virt-manager-wrapped)$,title:^.* - (Connection Details|连接详情)$"
    # The locked virt-manager UI title is translated by GtkBuilder; include its
    # Chinese catalogue string so the main-window rule survives zh_CN sessions.
    "${workspace},app_id:^(virt-manager|[.]virt-manager-wrapped)$,title:^(Virtual Machine Manager|虚拟系统管理器)$"

    # Preserve named scratch launch identities and their established sizes.
    "${opaque},app_id:^(kitty|mayon-scratch|mayon-files|mayon-monitor|mayon-clash|mayon-tools|mayon-bili|mayon-docker-exec|mayon-herdr)$"
    # TUI scratchpads share one centered, opaque Kitty window ratio.
    "is_named_scratchpad:1,width:0.78,height:0.78,app_id:^(mayon-scratch|mayon-files|mayon-monitor|mayon-clash|mayon-tools|mayon-bili)$"
    "${workspace},app_id:^(mayon-docker-exec)$"
  ]
  # Community modal/chooser patterns, scoped to apps and anchored to avoid
  # floating tabs such as "Save As - documentation — Mozilla Firefox".
  ++ forTitles dialogApps dialog [
    "^(Open|Open File|Open Files|Open Folder|Save|Save As|Save File|File Upload)$"
    "^(Select a File|Select Folder|Choose File|Choose Files|Choose Folder)$"
    "^(打开|打开文件|保存|保存文件|另存为|选择文件|选择文件夹)$"
    "^(Add Folder to Workspace|添加文件夹到工作区)$"
  ]
  ++ forTitles dialogApps dialog [
    "^(Preferences|Settings|Options|Properties)$"
    "^(首选项|偏好设置|设置|选项|属性)$"
  ]
  ++ forTitles dialogApps compact [
    "^(About|Confirmation|Confirm|Confirm Deletion|Authentication Required)$"
    "^(关于|确认|确认删除|需要认证)$"
  ]
  # Real login titles that are distinct from main windows. QQ/QQ and
  # wechat/Weixin are ambiguous in this build: do NOT float those main IDs.
  ++ forTitles communicationGroups compact [
    "^(Login|Log [Ii]n|Sign [Ii]n|QQ Login|WeChat Login|登录|扫码登录)$"
    "^(Vesktop Setup)$"
  ]
  ++ forTitles communicationGroups dialog [
    "^(Image Viewer|Photo Viewer|图片查看器|图片预览|查看图片)$"
    "^(Voice Call|Video Call|语音通话|视频通话|通话窗口)$"
  ]
  # Passive notifications keep existing silent semantics. Calls / login / main
  # chats stay focusable. Only sharing toolbars have persistent no_focus.
  ++ forTitles communicationGroups "${float},${silent},no_animation:1" [
    "^(Notification|通知|新消息提醒|消息通知|来电提醒)(.*)$"
    "^(截图)(.*)$"
  ]
  ++ forTitles communicationGroups "${float},no_focus:1,${silent},no_animation:1" [
    "^(Sharing Toolbar|Meeting Toolbar|Mini Window)(.*)$"
    "^Screen ?Shar(e|ing) (Toolbar|Indicator)(.*)$"
    "^(共享工具栏|会议悬浮窗|迷你窗口)(.*)$"
    "^屏幕共享(工具栏|悬浮条)(.*)$"
  ]
  # Retain the private opt-in hook; the real host never assigns app tags.
  ++ lib.optionals assignAppTags [
    "tags:2,is_tag_silent:1,app_id:^(${browser})$,title:.*Mozilla Firefox$"
  ]
  ++ lib.optionals assignAppTags (
    map (
      app:
      "tags:4,is_tag_silent:1,app_id:^(${app})$,title:^(QQ|微信|WeChat|Discord|Vesktop|腾讯会议|Tencent Meeting)$"
    ) communicationGroups
  );
in
assert lib.all (rule: builtins.stringLength " ${rule}" <= 255) rules;
lib.unique rules
