#!/usr/bin/env python3
"""Apply the small, pinned dwm-flexipatch configuration at build time."""
import argparse
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
for name in ("profile", "bg", "fg", "blue", "selection", "muted", "red", "deep", "surface", "font-mono", "font-cjk"):
    p.add_argument("--" + name, required=True)
p.add_argument("--dpi", required=True, type=int)
a = p.parse_args()
root = Path.cwd()

def scale(logical):
    return round(logical * a.dpi / 96)

flags = root / "patches.def.h"
s = flags.read_text()
enabled = {"BAR_SYSTRAY_PATCH", "BAR_HEIGHT_PATCH", "BAR_PADDING_PATCH", "CENTER_PATCH",
           "PERTAG_PATCH", "SCRATCHPADS_PATCH", "VANITYGAPS_PATCH",
           "FULLSCREEN_PATCH", "TOGGLEFULLSCREEN_PATCH", "BAR_STATUS2D_PATCH",
           "FOCUSONNETACTIVE_PATCH", "SAVEFLOATS_PATCH", "FLOATPOS_PATCH",
           "BAR_UNDERLINETAGS_PATCH"}
enabled.add("CENTER_TRANSIENT_WINDOWS_BY_PARENT_PATCH")
for name in enabled:
    s, n = re.subn(rf"(#define\s+{name}\s+)0\b", r"\g<1>1", s)
    if n != 1:
        raise SystemExit(f"expected one switch for {name}, found {n}")
flags.write_text(s)

c = root / "config.def.h"
s = c.read_text()
def once(pattern, repl):
    global s
    s, n = re.subn(pattern, repl, s, count=1, flags=re.S | re.M)
    if n != 1:
        raise SystemExit(f"configuration anchor missing: {pattern[:70]}")

for name, value in (("gappih", 10), ("gappiv", 10), ("gappoh", 14), ("gappov", 14)):
    once(rf"(static const unsigned int {name}\s*=\s*)\d+", rf"\g<1>{scale(value)}")
once(r"(static const int smartgaps_fact\s*=\s*)\d+", r"\g<1>1")
once(r"(static const int bar_height\s*=\s*)\d+", rf"\g<1>{scale(28)}")
once(r"(static const int vertpad\s*=\s*)\d+", rf"\g<1>{scale(10)}")
once(r"(static const int sidepad\s*=\s*)\d+", rf"\g<1>{scale(14)}")
once(r"(#else\s*\nstatic const unsigned int borderpx\s*=\s*)\d+", rf"\g<1>{scale(1)}")
once(r"(static const float mfact\s*=\s*)[0-9.]+", r"\g<1>0.60")
once(r"#define MODKEY Mod1Mask", "#define MODKEY Mod4Mask")
once(r'static const char \*termcmd\[\]\s*=\s*\{ "st", NULL \};', "")

# Use a mono face with fontconfig CJK fallback; the Xft DPI is provided by the host.
once(r"static const char \*fonts\[\]\s*=\s*\{[^}]*\};",
     'static const char *fonts[] = { '
     + ', '.join(json.dumps(f"{font}:size=9.5") for font in (a.font_mono, a.font_cjk)) + ' };')

# Underline only the active tag, keeping its label legible against the shared deep bar.
once(r"(static const unsigned int ulinepad\s*=\s*)\d+", rf"\g<1>{scale(5)}")
once(r"(static const unsigned int ulinestroke\s*=\s*)\d+", rf"\g<1>{scale(2)}")
once(r"(static const int ulineall\s*=\s*)\d+", r"\g<1>0")
once(r"(static const int ulinetop\s*=\s*)\d+", r"\g<1>0")

colors = {"normfgcolor": a.fg, "normbgcolor": a.deep, "normbordercolor": a.surface,
          "normfloatcolor": a.surface, "selfgcolor": a.blue, "selbgcolor": a.selection,
          "selbordercolor": a.blue, "selfloatcolor": a.selection,
          "titlenormfgcolor": a.fg, "titlenormbgcolor": a.deep,
          "titlenormbordercolor": a.surface, "titlenormfloatcolor": a.surface,
          "titleselfgcolor": a.blue, "titleselbgcolor": a.selection,
          "titleselbordercolor": a.blue, "titleselfloatcolor": a.selection,
          "tagsnormfgcolor": a.muted, "tagsnormbgcolor": a.deep,
          "tagsnormbordercolor": a.surface, "tagsnormfloatcolor": a.surface,
          "tagsselfgcolor": a.blue, "tagsselbgcolor": a.selection,
          "tagsselbordercolor": a.blue, "tagsselfloatcolor": a.selection,
          "hidnormfgcolor": a.muted, "hidselfgcolor": a.blue,
          "urgfgcolor": a.deep, "urgbgcolor": a.red, "urgbordercolor": a.red}
for key, value in colors.items():
    # C theme entries use these exact names; set the color in each declaration.
    s, n = re.subn(rf'(^static char {key}\[\]\s*=\s*)"#[0-9A-Fa-f]{{6}}"',
                   rf'\g<1>"{value}"', s, count=1, flags=re.M)
    if n != 1:
        raise SystemExit(f"expected one color declaration for {key}, found {n}")

# Scratchpads are Kitty instances and are separate from normal terminal launches.
once(r"#elif SCRATCHPADS_PATCH\nconst char \*spcmd1\[\].*?\n#endif // SCRATCHPADS_PATCH",
     '#elif SCRATCHPADS_PATCH\n'
     f'const char *spcmd1[] = {{ "{a.profile}/bin/kitty", "--class=kitty", "--name=mayon-scratch-term", NULL }};\n'
     f'const char *spcmd2[] = {{ "{a.profile}/bin/kitty", "--class=kitty", "--name=mayon-scratch-yazi", "{a.profile}/bin/yazi", NULL }};\n'
     'static Sp scratchpads[] = { {"scratch-term", spcmd1}, {"scratch-yazi", spcmd2} };\n'
     '#endif // SCRATCHPADS_PATCH')

# Rules keep the main QQ/meeting windows tiled; only recognized utility classes and dialogs float.
once(r"static const Rule rules\[\] = \{.*?\n\};",
     'static const Rule rules[] = {\n'
     '\tRULE(.wintype = WTYPE "DIALOG", .isfloating = 1, .iscentered = 1)\n'
     '\tRULE(.wintype = WTYPE "UTILITY", .isfloating = 1, .iscentered = 1)\n'
     '\tRULE(.wintype = WTYPE "SPLASH", .isfloating = 1, .iscentered = 1)\n'
     '\tRULE(.class = "Pavucontrol", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '\tRULE(.class = "Nm-connection-editor", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 60% 65%")\n'
     '\tRULE(.class = "Blueman-manager", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 60% 65%")\n'
     '\tRULE(.class = "Fcitx5-config-qt", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '\tRULE(.class = "qt6ct", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '\tRULE(.class = "xorg-help", .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '\tRULE(.instance = "mayon-scratch-term", .tags = SPTAG(0), .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '\tRULE(.instance = "mayon-scratch-yazi", .tags = SPTAG(1), .isfloating = 1, .iscentered = 1, .floatpos = "50% 50% 65% 70%")\n'
     '};')

# Replace the key table without enabling unrelated flexipatch key modes.
keyblock = '''static const Key keys[] = {
\t{ MODKEY, XK_Return, spawn, CMD("PROFILE/bin/workspace-terminal") },
\t{ MODKEY, XK_b, spawn, CMD("PROFILE/bin/workspace-browser") },
\t{ MODKEY, XK_e, spawn, CMD("PROFILE/bin/workspace-files") },
\t{ Mod1Mask, XK_space, spawn, CMD("PROFILE/bin/xorg-launcher") },
\t{ MODKEY, XK_v, spawn, CMD("PROFILE/bin/copyq", "toggle") },
\t{ MODKEY|Mod1Mask, XK_l, spawn, CMD("PROFILE/bin/xorg-lock") },
\t{ MODKEY, XK_p, spawn, CMD("PROFILE/bin/xorg-session-menu") },
\t{ MODKEY, XK_F1, spawn, CMD("PROFILE/bin/xorg-session-help") },
\t{ MODKEY|ShiftMask, XK_e, spawn, CMD("PROFILE/bin/xorg-session-menu") },
\t{ MODKEY, XK_j, focusstack, {.i = +1} },
\t{ MODKEY, XK_k, focusstack, {.i = -1} },
\t{ MODKEY, XK_q, killclient, {0} },
\t{ MODKEY, XK_t, setlayout, {.v = &layouts[0]} },
\t{ MODKEY, XK_m, setlayout, {.v = &layouts[2]} },
\t{ MODKEY|ShiftMask, XK_t, setlayout, {.v = &layouts[1]} },
\t{ MODKEY|ControlMask, XK_Return, zoom, {0} },
\t{ MODKEY, XK_i, incnmaster, {.i = +1} },
\t{ MODKEY, XK_u, incnmaster, {.i = -1} },
\t{ MODKEY, XK_comma, focusmon, {.i = -1} },
\t{ MODKEY, XK_period, focusmon, {.i = +1} },
\t{ MODKEY|ShiftMask, XK_comma, tagmon, {.i = -1} },
\t{ MODKEY|ShiftMask, XK_period, tagmon, {.i = +1} },
\t{ MODKEY, XK_h, setmfact, {.f = -0.05} },
\t{ MODKEY, XK_l, setmfact, {.f = +0.05} },
\t{ MODKEY|ShiftMask, XK_space, togglefloating, {0} },
\t{ MODKEY, XK_f, togglefullscreen, {0} },
\t{ MODKEY|ShiftMask, XK_g, togglegaps, {0} },
\t{ MODKEY|ShiftMask, XK_Return, togglescratch, {.ui = 0} },
\t{ MODKEY|Mod1Mask, XK_e, togglescratch, {.ui = 1} },
\t{ MODKEY, XK_Tab, view, {.ui = 0} },
\t{ MODKEY, XK_1, view, {.ui = 1 << 0} }, { MODKEY|ShiftMask, XK_1, tag, {.ui = 1 << 0} },
\t{ MODKEY, XK_2, view, {.ui = 1 << 1} }, { MODKEY|ShiftMask, XK_2, tag, {.ui = 1 << 1} },
\t{ MODKEY, XK_3, view, {.ui = 1 << 2} }, { MODKEY|ShiftMask, XK_3, tag, {.ui = 1 << 2} },
\t{ MODKEY, XK_4, view, {.ui = 1 << 3} }, { MODKEY|ShiftMask, XK_4, tag, {.ui = 1 << 3} },
\t{ MODKEY, XK_5, view, {.ui = 1 << 4} }, { MODKEY|ShiftMask, XK_5, tag, {.ui = 1 << 4} },
\t{ MODKEY, XK_6, view, {.ui = 1 << 5} }, { MODKEY|ShiftMask, XK_6, tag, {.ui = 1 << 5} },
\t{ MODKEY, XK_7, view, {.ui = 1 << 6} }, { MODKEY|ShiftMask, XK_7, tag, {.ui = 1 << 6} },
\t{ MODKEY, XK_8, view, {.ui = 1 << 7} }, { MODKEY|ShiftMask, XK_8, tag, {.ui = 1 << 7} },
\t{ MODKEY, XK_9, view, {.ui = 1 << 8} }, { MODKEY|ShiftMask, XK_9, tag, {.ui = 1 << 8} },
\t{ 0, XF86XK_AudioRaiseVolume, spawn, CMD("PROFILE/bin/xorg-audio", "up") },
\t{ 0, XF86XK_AudioLowerVolume, spawn, CMD("PROFILE/bin/xorg-audio", "down") },
\t{ 0, XF86XK_AudioMute, spawn, CMD("PROFILE/bin/xorg-audio", "mute") },
\t{ 0, XF86XK_MonBrightnessUp, spawn, CMD("PROFILE/bin/xorg-brightness", "up") },
\t{ 0, XF86XK_MonBrightnessDown, spawn, CMD("PROFILE/bin/xorg-brightness", "down") },
\t{ 0, XF86XK_AudioPlay, spawn, CMD("PROFILE/bin/xorg-media", "play-pause") },
\t{ 0, XF86XK_AudioNext, spawn, CMD("PROFILE/bin/xorg-media", "next") },
\t{ 0, XF86XK_AudioPrev, spawn, CMD("PROFILE/bin/xorg-media", "previous") },
\t{ 0, XK_Print, spawn, CMD("PROFILE/bin/xorg-screenshot", "region") },
\t{ ControlMask, XK_Print, spawn, CMD("PROFILE/bin/xorg-screenshot", "screen") },
};'''.replace("PROFILE", a.profile)
once(r"static const Key keys\[\] = \{.*?\n\};", keyblock)
once(r"#define MODKEY Mod4Mask\n", "#define MODKEY Mod4Mask\n")

# The status area is the shared session menu entry point; preserve tag/client mouse actions.
statusbuttons = ('\t{ ClkStatusText,        0,                   Button1,        spawn, '
                 f'{{.v = (const char*[]){{ "{a.profile}/bin/xorg-session-menu", NULL }}}} }},\n')
once(r"\t#if BAR_STATUSCMD_PATCH && BAR_DWMBLOCKS_PATCH\n.*?\t#endif // BAR_STATUSCMD_PATCH\n",
     statusbuttons)
c.write_text(s)

# The upstream config references XFree86 keysyms; include the header explicitly.
d = root / "dwm.c"
ds = d.read_text()
if "#include <X11/XF86keysym.h>" not in ds:
    ds = ds.replace("#include <X11/Xlib.h>", "#include <X11/Xlib.h>\n#include <X11/XF86keysym.h>", 1)

# Export a stable CARDINAL consumed by Picom. Update after manage/toggle/fullscreen,
# and remove it when a client leaves the WM. Fullscreen is treated as floating.
ds = ds.replace("static Atom wmatom[WMLast], netatom[NetLast];",
                "static Atom wmatom[WMLast], netatom[NetLast];\nstatic Atom mayonfloatingatom;")
anchor = "void\napplyrules(Client *c)\n{"
helper = '''static void
updatefloatingproperty(Client *c)
{
\tunsigned long value = c->isfloating ? 1UL : 0UL;
\tif (mayonfloatingatom != None)
\t\tXChangeProperty(dpy, c->win, mayonfloatingatom, XA_CARDINAL, 32,
\t\t                PropModeReplace, (unsigned char *)&value, 1);
}

'''
if "updatefloatingproperty(Client *c)" not in ds:
    ds = ds.replace(anchor, helper + anchor, 1)
ds = ds.replace("wmatom[WMDelete] = XInternAtom(dpy, \"WM_DELETE_WINDOW\", False);",
                "wmatom[WMDelete] = XInternAtom(dpy, \"WM_DELETE_WINDOW\", False);\n\tmayonfloatingatom = XInternAtom(dpy, \"_MAYON_DWM_FLOATING\", False);")
ds = ds.replace("\t\tXSetWindowBorder(dpy, w, scheme[SchemeNorm][ColFloat].pixel);\n\t}\n\t#if ATTACHABOVE_PATCH",
                "\t\tXSetWindowBorder(dpy, w, scheme[SchemeNorm][ColFloat].pixel);\n\t}\n\tupdatefloatingproperty(c);\n\t#if ATTACHABOVE_PATCH")
ds = ds.replace("c->isfloating = !c->isfloating || c->isfixed;",
                "c->isfloating = !c->isfloating || c->isfixed;\n\tupdatefloatingproperty(c);")
ds = ds.replace("\t\tc->isfloating = 1;", "\t\tc->isfloating = 1;\n\t\tupdatefloatingproperty(c);")
ds = ds.replace("\t\tc->isfloating = c->oldstate;", "\t\tc->isfloating = c->oldstate;\n\t\tupdatefloatingproperty(c);")
# In upstream native fullscreen mode both transition branches already resize the
# client. The unconditional trailing resize overwrites resizeclient's saved old
# geometry with the fullscreen dimensions, so leaving fullscreen stays fullscreen.
fullscreen_tail = "\tresizeclient(c, c->x, c->y, c->w, c->h);\n}\n#endif // FAKEFULLSCREEN_CLIENT_PATCH"
if ds.count(fullscreen_tail) != 1:
    raise SystemExit(f"expected the single native fullscreen tail resize, found {ds.count(fullscreen_tail)}")
ds = ds.replace(fullscreen_tail,
                "}\n#endif // FAKEFULLSCREEN_CLIENT_PATCH", 1)
# Unmanaged non-destroyed clients lose the WM-owned hint; destroyed windows need no X request.
ds = ds.replace("void\nunmanage(Client *c, int destroyed)\n{",
                "void\nunmanage(Client *c, int destroyed)\n{\n\tif (!destroyed)\n\t\tXDeleteProperty(dpy, c->win, mayonfloatingatom);")
# Only pager-originated _NET_ACTIVE_WINDOW requests may switch tags/focus.
ds = ds.replace("} else if (cme->message_type == netatom[NetActiveWindow]) {",
                "} else if (cme->message_type == netatom[NetActiveWindow] && cme->data.l[0] == 2) {")
# Clients can become floating through changed transient state.
ds = ds.replace("c->isfloating = (wintoclient(trans)) != NULL))\n\t\t\t\tarrange(c->mon);",
                "c->isfloating = (wintoclient(trans)) != NULL)) {\n\t\t\t\tupdatefloatingproperty(c);\n\t\t\t\tarrange(c->mon);\n\t\t\t}")
# Bound initial floating utilities and dialogs to 70% of the work area before centering.
sizeanchor = "\tif (c->x + WIDTH(c) > c->mon->wx + c->mon->ww)"
clamp = '''\tif (c->isfloating) {
\t\tint maxw = c->mon->ww * 7 / 10;
\t\tint maxh = c->mon->wh * 7 / 10;
\t\tif (c->w > maxw) c->w = maxw;
\t\tif (c->h > maxh) c->h = maxh;
\t}
'''
if sizeanchor not in ds:
    raise SystemExit("manage geometry clamp anchor missing")
ds = ds.replace(sizeanchor, clamp + sizeanchor, 1)

required_source = [
    'mayonfloatingatom = XInternAtom(dpy, "_MAYON_DWM_FLOATING", False);',
    'XChangeProperty(dpy, c->win, mayonfloatingatom, XA_CARDINAL, 32,',
    'XDeleteProperty(dpy, c->win, mayonfloatingatom);',
    'if (cme->message_type == netatom[NetActiveWindow] && cme->data.l[0] == 2)',
    'int maxw = c->mon->ww * 7 / 10;',
]
missing = [fragment for fragment in required_source if fragment not in ds]
if missing:
    raise SystemExit("required dwm source integration missing: " + ", ".join(missing))
if ds.count("updatefloatingproperty(c);") < 6:
    raise SystemExit("floating-property updates no longer cover the expected client paths")
d.write_text(ds)
