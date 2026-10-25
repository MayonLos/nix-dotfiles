#!/usr/bin/env python3
"""Apply the small, pinned dwm-flexipatch configuration at build time."""
import argparse
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
for name in ("profile", "bg", "fg", "blue", "selection", "muted", "red", "deep", "surface", "font-mono", "font-cjk"):
    p.add_argument("--" + name, required=True)
p.add_argument("--bindings", required=True)
p.add_argument("--rules", required=True)
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
enabled.update({"CENTER_TRANSIENT_WINDOWS_BY_PARENT_PATCH", "FOCUSDIR_PATCH",
                "FOCUSADJACENTTAG_PATCH", "CYCLELAYOUTS_PATCH", "SWAPFOCUS_PATCH",
                "STICKY_PATCH", "ALWAYSONTOP_PATCH", "BORDER_RULE_PATCH",
                "MONOCLESYMBOL_PATCH", "VANITYGAPS_MONOCLE_PATCH", "BAR_EWMHTAGS_PATCH"})
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
once(r"(static const int bar_height\s*=\s*)\d+", rf"\g<1>{scale(30)}")
once(r"(static const int vertpad\s*=\s*)\d+", rf"\g<1>{scale(6)}")
once(r"(static const int sidepad\s*=\s*)\d+", rf"\g<1>{scale(8)}")
once(r"(#else\s*\nstatic const unsigned int borderpx\s*=\s*)\d+", rf"\g<1>{scale(2)}")
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
          "normfloatcolor": a.surface, "selfgcolor": a.blue, "selbgcolor": a.deep,
          "selbordercolor": a.blue, "selfloatcolor": a.blue,
          "titlenormfgcolor": a.fg, "titlenormbgcolor": a.deep,
          "titlenormbordercolor": a.surface, "titlenormfloatcolor": a.surface,
          "titleselfgcolor": a.fg, "titleselbgcolor": a.deep,
          "titleselbordercolor": a.blue, "titleselfloatcolor": a.selection,
          "tagsnormfgcolor": a.muted, "tagsnormbgcolor": a.deep,
          "tagsnormbordercolor": a.surface, "tagsnormfloatcolor": a.surface,
          "tagsselfgcolor": a.fg, "tagsselbgcolor": a.deep,
          "tagsselbordercolor": a.blue, "tagsselfloatcolor": a.selection,
          "hidnormfgcolor": a.muted, "hidselfgcolor": a.blue,
          "urgfgcolor": a.red, "urgbgcolor": a.deep, "urgbordercolor": a.red}
for key, value in colors.items():
    # C theme entries use these exact names; set the color in each declaration.
    s, n = re.subn(rf'(^static char {key}\[\]\s*=\s*)"#[0-9A-Fa-f]{{6}}"',
                   rf'\g<1>"{value}"', s, count=1, flags=re.M)
    if n != 1:
        raise SystemExit(f"expected one color declaration for {key}, found {n}")

# The resource tables are the only source of keys and narrow window rules.
once(r"#elif SCRATCHPADS_PATCH\nconst char \*spcmd1\[\].*?\n#endif // SCRATCHPADS_PATCH",
     '#elif SCRATCHPADS_PATCH\n'
     + ''.join(f'const char *spcmd{i+1}[] = {{ "{a.profile}/bin/kitty", "--class=kitty", "--name=mayon-scratch-{name}"{extra}, NULL }};\n'
               for i, (name, extra) in enumerate([("term", ""), ("yazi", f', "{a.profile}/bin/yazi"'), ("monitor", f', "{a.profile}/bin/btop"')]))
     + 'static Sp scratchpads[] = { {"term", spcmd1}, {"yazi", spcmd2}, {"monitor", spcmd3} };\n'
     + '#endif // SCRATCHPADS_PATCH')
rule_rows = json.loads(Path(a.rules).read_text())
rule_lines = []
for row in rule_rows:
    values = []
    for k, v in row.items():
        if k == "wintype": v = 'WTYPE ' + json.dumps(v)
        elif k in ("class", "instance", "title", "floatpos"): v = json.dumps(v, ensure_ascii=False)
        else: v = str(v)
        values.append(f'.{k} = {v}')
    rule_lines.append('\tRULE(' + ', '.join(values) + ')')
once(r"static const Rule rules\[\] = \{.*?\n\};", 'static const Rule rules[] = {\n' + '\n'.join(rule_lines) + '\n};')
modifiers = {"Super": "MODKEY", "Shift": "ShiftMask", "Ctrl": "ControlMask", "Alt": "Mod1Mask"}
key_lines = []
for row in json.loads(Path(a.bindings).read_text()):
    mods = '|'.join(modifiers[m] for m in row['mods'].split('+') if m) or '0'
    key = ('XF86XK_' + row['key'][4:]) if row['key'].startswith('XF86') else 'XK_' + row['key']
    if row['kind'] == 'command':
        args = [f'{a.profile}/bin/{row["arg"][0]}'] + row['arg'][1:]
        arg = 'CMD(' + ', '.join(json.dumps(v, ensure_ascii=False) for v in args) + ')'
    elif row['kind'] == 'raw': arg = '{0}'
    else: arg = '{.' + row['kind'] + ' = ' + row['arg'] + '}'
    key_lines.append(f'\t{{ {mods}, {key}, {row["function"]}, {arg} }},')
once(r"static const Key keys\[\] = \{.*?\n\};", 'static const Key keys[] = {\n' + '\n'.join(key_lines) + '\n};')

# Allocate the clock first to reserve the true monitor center. Remaining left
# and right modules use the barmodules allocator, including its width clipping.
once(r"static const BarRule barrules\[\] = \{.*?\n\};", """static const BarRule barrules[] = {
    { -1, 0, BAR_ALIGN_CENTER, width_mayonclock, draw_mayonclock, NULL, NULL, "clock" },
    { -1, 0, BAR_ALIGN_LEFT, width_tags, draw_tags, click_tags, hover_tags, "tags" },
    { -1, 0, BAR_ALIGN_LEFT, width_mayonsep, draw_mayonsep, NULL, NULL, "separator" },
    { -1, 0, BAR_ALIGN_LEFT, width_ltsymbol, draw_ltsymbol, click_ltsymbol, NULL, "layout" },
    { -1, 0, BAR_ALIGN_LEFT, width_mayonsep, draw_mayonsep, NULL, NULL, "separator" },
    {  0, 0, BAR_ALIGN_RIGHT_RIGHT, width_systray, draw_systray, click_systray, NULL, "systray" },
    { -1, 0, BAR_ALIGN_RIGHT_RIGHT, width_status2d, draw_mayonstatus, click_status2d, NULL, "status2d" },
    { -1, 0, BAR_ALIGN_LEFT, width_wintitle, draw_wintitle, click_wintitle, NULL, "title" },
};""")
s = s.replace('"[]=",      tile', '"Tile",     tile').replace('"><>",      NULL', '"Float",    NULL').replace('"[M]",      monocle', '"Mono",     monocle')
# The status area is the shared session menu entry point; preserve tag/client mouse actions.
statusbuttons = ('\t{ ClkStatusText,        0,                   Button1,        spawn, '
                 f'{{.v = (const char*[]){{ "{a.profile}/bin/xorg-session-menu", NULL }}}} }},\n')
once(r"\t#if BAR_STATUSCMD_PATCH && BAR_DWMBLOCKS_PATCH\n.*?\t#endif // BAR_STATUSCMD_PATCH\n",
     statusbuttons)
c.write_text(s)

# Local declarations used by config.h must precede that include.
# The upstream config references XFree86 keysyms; include the header explicitly.
d = root / "dwm.c"
ds = d.read_text()
ds = ds.replace("#include <regex.h>\n", "")
ds = ds.replace("#include <X11/Xlib.h>", "#include <regex.h>\n#include <X11/Xlib.h>", 1)
if "#include <X11/XF86keysym.h>" not in ds:
    ds = ds.replace("#include <X11/Xlib.h>", "#include <X11/Xlib.h>\n#include <X11/XF86keysym.h>", 1)

prototypes = """static int width_mayonclock(Bar *, BarArg *);
static int draw_mayonclock(Bar *, BarArg *);
static int draw_mayonstatus(Bar *, BarArg *);
static int width_mayonsep(Bar *, BarArg *);
static int draw_mayonsep(Bar *, BarArg *);
static void mayontagfollow(const Arg *);
static void mayoncenter(const Arg *);
static void mayonmaximize(const Arg *);
static void mayonmove(const Arg *);
static void updatefloatingproperty(Client *);
"""
ds = ds.replace('#include "config.h"', prototypes + '#include "config.h"')
ds = ds.replace('#include "patch/include.c"', '#include "patch/include.c"\n#include "mayon.c"')
ds = ds.replace('int isfixed, isfloating, isurgent, neverfocus, oldstate, isfullscreen;',
                'int isfixed, isfloating, isurgent, neverfocus, oldstate, isfullscreen;\n'
                '\tint mayonpassive, mayongame, mayonmax, mayonoldfloat, mayonx, mayony, mayonw, mayonh;')
ds = ds.replace('const char *wintype;', 'const char *wintype;\n\tint mayonpassive, mayongame, mayonsticky, mayontop;')
for field, text in [('title','c->name'), ('class','class'), ('instance','instance')]:
    ds = ds.replace(f'!r->{field} || strstr({text}, r->{field})', f'mayonmatch(r->{field}, {text})')
ds = ds.replace('c->isfloating = r->isfloating;',
                'c->isfloating = r->isfloating;\n\t\t\tc->mayonpassive = r->mayonpassive;\n'
                '\t\t\tc->mayongame = r->mayongame;\n\t\t\tc->issticky = r->mayonsticky;\n'
                '\t\t\tc->alwaysontop = r->mayontop;')
# The terminal manage() focus(NULL) normally picks the newest stack entry.
# Retain the existing selection for passive surfaces without making them
# permanently unfocusable; explicit clicks and pager selection still work.
manage_focus = "\tfocus(NULL);\n\n\t#if BAR_EWMHTAGS_PATCH\n\tsetfloatinghint(c);\n\t#endif // BAR_EWMHTAGS_PATCH\n}"
if ds.count(manage_focus) != 1:
    raise SystemExit("manage final focus anchor changed")
ds = ds.replace(manage_focus, manage_focus.replace("focus(NULL)", "focus(c->mayonpassive ? selmon->sel : NULL)"), 1)
# Passive surfaces opt out of pointer-enter focus too. Mapping under the pointer
# can generate EnterNotify after manage(); explicit click/pager focus still works.
enter_anchor = "\tc = wintoclient(ev->window);\n\tm = c ? c->mon : wintomon(ev->window);"
if ds.count(enter_anchor) != 1:
    raise SystemExit("enternotify client anchor changed")
ds = ds.replace(enter_anchor, enter_anchor.replace("\n\tm =", "\n\tif (c && c->mayonpassive) return;\n\tm ="), 1)
# Passive mapping keeps keyboard focus; a click can still interact with it.
ds = ds.replace('if (c->mon == selmon)\n\t\tunfocus(selmon->sel, 0, c);\n\tc->mon->sel = c;',
                'if (!c->mayonpassive) {\n\t\tif (c->mon == selmon) unfocus(selmon->sel, 0, c);\n\t\tc->mon->sel = c;\n\t}')
ds = ds.replace('XClassHint ch = {"dwm", "dwm"};', 'XClassHint ch = {"dwm-bar", "dwm-bar"};')
ds = ds.replace('if ((ev->window == root) && (ev->atom == XA_WM_NAME)) {',
                'if (ev->window == root && ev->atom == XInternAtom(dpy, "_MAYON_DWM_CLOCK", False)) {\n'
                '\t\tdrawbars();\n\t} else if ((ev->window == root) && (ev->atom == XA_WM_NAME)) {')

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
	value = c->mayongame ? 1UL : 0UL;
	XChangeProperty(dpy, c->win, XInternAtom(dpy, "_MAYON_DWM_GAME", False), XA_CARDINAL, 32,
	                PropModeReplace, (unsigned char *)&value, 1);
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
# Bound initial floating utilities and dialogs to 80% of the work area before centering.
sizeanchor = "\tif (c->x + WIDTH(c) > c->mon->wx + c->mon->ww)"
clamp = '''\tif (c->isfloating) {
\t\tint maxw = c->mon->ww * 8 / 10;
\t\tint maxh = c->mon->wh * 8 / 10;
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
    'int maxw = c->mon->ww * 8 / 10;',
]
missing = [fragment for fragment in required_source if fragment not in ds]
if missing:
    raise SystemExit("required dwm source integration missing: " + ", ".join(missing))
if ds.count("updatefloatingproperty(c);") < 6:
    raise SystemExit("floating-property updates no longer cover the expected client paths")
d.write_text(ds)

# Small outputs keep the title inside its allocated side of the centered clock.
title = root / "patch/bar_wintitle.c"
ts = title.read_text()
anchor = "\tMonitor *m = bar->mon;"
if ts.count(anchor) != 1:
    raise SystemExit("title allocation anchor changed")
ts = ts.replace(anchor, "\tif (w <= lrpad) return 0;\n" + anchor, 1)
ts = re.sub(r"\tdrawstateindicator\(m, c, 1, x, a->y, w, a->h, 0, 0, c->isfixed\);", "", ts)
title.write_text(ts)
