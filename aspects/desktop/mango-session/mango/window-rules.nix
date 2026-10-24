# Private rule table; later matches override earlier properties (tags accumulate).
# Source of truth: locked Mango 0.18.3 option_defs.c / client_apply_rules().
{
  lib,
  assignAppTags ? false,
}:
let
  float = "is_floating:1";
  centered = "${float},width:0.60,height:0.65";
  tools = "${float},width:0.34,height:0.52,offset_x:92,offset_y:-90";
  silent = "is_open_silent:1,is_tag_silent:1";
  communicationGroups = [
    "(QQ|qq|com[.]qq[.]QQ)"
    "(wechat|WeChat|weixin|com[.]tencent[.](WeChat|wechat))"
    "(discord|Discord|vesktop|Vesktop)"
    "(wemeet|wemeetapp|TencentMeeting)"
  ];
  game = "^(steam_app_[0-9]+|Minecraft.*|minecraft.*|com[.]mojang[.]Minecraft.*)$";
in
[
  # With allow_tearing=2, opt every normal client out; games opt in below.
  "force_tearing:0,app_id:.*"

  # Standard transient/dialog types already float and center in Mango. These
  # cover standalone helpers / file pickers lacking a transient parent.
  "${centered},app_id:^(xdg-desktop-portal-gtk|xdg-desktop-portal-gnome)$"
  "${float},width:0.38,height:0.32,app_id:^(polkit-gnome-authentication-agent-1|lxqt-policykit-agent|org[.]kde[.]polkit-kde-authentication-agent-1|pinentry.*)$"
  "${centered},app_id:^([Ff]irefox|[Tt]hunar|org[.]gtk[.]GtkFileChooserDialog)$,title:^(Open File|Save As|Save File|File Upload|Select Folder|Choose File|打开文件|保存文件|另存为|选择文件夹)$"
  "${float},width:0.42,height:0.30,app_id:^[Tt]hunar$,title:^(Rename|重命名)"
  "${float},width:0.68,height:0.82,app_id:^dev[.]noctalia[.]Noctalia$"

  # Preserve client size/aspect hints. Initial 16:9 size; overlay is above
  # normal/fullscreen clients, global means this output's tags (not all outputs).
  "${float},is_global:1,is_overlay:1,${silent},width:480,height:270,offset_x:96,offset_y:92,app_id:^[Ff]irefox$,title:^(Picture-in-Picture|画中画)$"
  "${float},width:0.60,height:0.64,app_id:^(mpv|imv|swayimg)$"

  # Small control tools stay near the bar; no missing app is implicitly installed.
  "${tools},app_id:^(org[.]pulseaudio[.]pavucontrol|pavucontrol|[Bb]lueman-manager|nm-connection-editor)$"
  "${float},width:0.26,height:0.46,app_id:^(org[.]gnome[.]Calculator|qalculate-gtk|qalculate-qt|Qalculate-gtk|kcalc)$"
  "${float},width:0.38,height:0.48,app_id:^(gcolor3|org[.]gnome[.]Gcolor3|org[.]kde[.]kcolorchooser|hyprpicker)$"
  # mark-shot's capture overlay is layer-shell; only its editor is a toplevel.
  "${float},no_animation:1,app_id:^(mark-shot|markshot|MarkShot)$"

  # Never force steam_app_* helpers fullscreen: honor each game's own request.
  # Mango removes fullscreen borders/dim/shadows natively; these rules also
  # remove decoration/animation for the game's windowed launch transition.
  "no_border:1,no_shadow:1,no_radius:1,no_animation:1,force_tearing:1,vrr_only_fullscreen:1,app_id:${game}"
  "${float},width:0.32,height:0.60,app_id:^([Ss]team|steamwebhelper)$,title:^(Friends List|Steam - Friends|好友列表|好友与聊天)$"
  "${float},${silent},no_animation:1,app_id:^([Ss]team|steamwebhelper)$,title:^(Notification|Steam Notification|通知)"
  "${centered},app_id:^(org[.]prismlauncher[.]PrismLauncher|PrismLauncher|prismlauncher)$,title:^(Console|Minecraft Log|Edit Instance|Instance Settings|实例设置|控制台)(.*)$"

  # Named scratch tools preserve their existing launch/keybind identities.
  "focused_opacity:1.0,unfocused_opacity:1.0,app_id:^(kitty|mayon-scratch|mayon-files|mayon-monitor)$"
  "is_named_scratchpad:1,width:0.78,height:0.78,app_id:^mayon-scratch$"
  "is_named_scratchpad:1,width:0.78,height:0.78,app_id:^mayon-files$"
  "is_named_scratchpad:1,width:0.72,height:0.74,app_id:^mayon-monitor$"
]
# Keep each UTF-8 config value within Mango's 255-byte parser buffer.
# Only passive overlays are silent; main chat/login/call windows still focus.
++ builtins.concatMap (
  app:
  map (title: "${float},${silent},no_animation:1,app_id:^${app}$,title:^${title}(.*)$") [
    "(Notification|通知|新消息提醒|消息通知|来电提醒)"
    "(Screen ?Share|Sharing Toolbar|Meeting Toolbar|Mini Window)"
    "(截图|屏幕共享|共享工具栏|会议悬浮窗|迷你窗口)"
  ]
) communicationGroups
# Existing habits have no fixed app destinations. Opt-in only, with silent tag
# assignment so launch does not switch the current view. `tags` are 1-based.
++ lib.optionals assignAppTags [
  "tags:2,is_tag_silent:1,app_id:^[Ff]irefox$,title:.*Mozilla Firefox$"
]
++ lib.optionals assignAppTags (
  map (
    app:
    "tags:4,is_tag_silent:1,app_id:^${app}$,title:^(QQ|微信|WeChat|Discord|Vesktop|腾讯会议|Tencent Meeting)$"
  ) communicationGroups
)
