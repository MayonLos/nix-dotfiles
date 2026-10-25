#!/usr/bin/env bash
set -euo pipefail

unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS SWAYSOCK
export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_DATA_HOME="$TMPDIR/data" XDG_CACHE_HOME="$TMPDIR/cache"
export GSETTINGS_BACKEND=keyfile GTK_A11Y=none LC_ALL=C.UTF-8
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$out"/{gtk-3.0,gtk-4.0,qt6ct}
test -f "$GTK_THEME_PACKAGE/share/themes/$GTK_THEME_NAME/gtk-3.0/gtk.css"
test -f "$ICON_PACKAGE/share/icons/$ICON_NAME/index.theme"
test -f "$ICON_PACKAGE/share/icons/$ICON_NAME/scalable/places/folder.svg"
# Offline CLI only: explicit templates/custom colors, no built-in apply hooks.
"$NOCTALIA" theme --theme-json "$THEME_JSON" --config "$CUSTOM_COLORS" \
  --render "$ASSETS/templates/gtk/gtk3.css:$out/gtk-3.0/noctalia.css" \
  --render "$ASSETS/templates/gtk/gtk4.css:$out/gtk-4.0/noctalia.css" \
  --render "$ASSETS/templates/qt/qtct.conf:$out/qt6ct/noctalia.conf" > "$out/render.log" 2>&1
for version in 3 4; do
  # No GTK extensions are enabled by this feature. The live writer creates
  # this optional import; the parser fixture supplies the empty equivalent.
  touch "$out/gtk-$version.0/noctalia-extensions.css"
  python3 "$CHECK_CSS" "$version.0" "$out/gtk-$version.0/noctalia.css"
done
cp "$QSS_SOURCE" "$out/qt6ct/one-dark.qss"
run() { "$@"; }
source "$QT_SEED"
cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/seed.conf"
python3 - "$PALETTE_JSON" "$out" <<'PY'
import configparser, json, pathlib, sys, tinycss2
p=json.loads(pathlib.Path(sys.argv[1]).read_text()); out=pathlib.Path(sys.argv[2])
gtk3=(out/'gtk-3.0/noctalia.css').read_text(); gtk4=(out/'gtk-4.0/noctalia.css').read_text()
for css in (gtk3, gtk4):
    assert '{{' not in css and '@font' not in css
    assert not [r for r in tinycss2.parse_stylesheet(css) if r.type=='error']
rules={tinycss2.serialize(r.prelude).strip(): tinycss2.serialize(r.content) for r in tinycss2.parse_stylesheet(gtk3) if r.type=='qualified-rule'}
sidebar=next(v for k,v in rules.items() if '.shortcuts-pane treeview.view:selected' in k)
assert 'inset 2px 0 '+p['blue'] in sidebar and '@selected_bg_color' in sidebar
icons=next(v for k,v in rules.items() if 'widget.view:selected' in k)
assert 'background-color: transparent' in icons and 'linear-gradient' in icons
details=next(v for k,v in rules.items() if 'treeview.view:selected' in k and 'filechooser' in k)
assert 'box-shadow: none' in details
assert '--sidebar-bg-color: '+p['deep'] in gtk4
assert '--window-bg-color: '+p['bg'] in gtk4
assert '--accent-color: '+p['blue'] in gtk4
qss=(out/'qt6ct/one-dark.qss').read_text()
assert '@BG@' not in qss and p['blue'] in qss and p['fonts']['mono'] in qss
scheme=configparser.ConfigParser(); scheme.read(out/'qt6ct/noctalia.conf')
for group in ('active_colors','inactive_colors','disabled_colors'):
    assert len(scheme['ColorScheme'][group].split(','))==22
assert [v.strip() for v in scheme['ColorScheme']['active_colors'].split(',')][12]==p['selection']
seed=configparser.ConfigParser();seed.read(out/'qt6ct/seed.conf')
assert seed['Appearance']['style']=='Fusion'
assert seed['Appearance']['icon_theme']==p['iconTheme']
assert seed['Appearance']['custom_palette']=='true'
assert seed['Interface']['stylesheets'].endswith('/qt6ct/qss/one-dark.qss')
PY
# A real Qt QSettings reader verifies list encoding after the actual activation.
cat > qt-settings.cpp <<'CPP'
#include <QCoreApplication>
#include <QSettings>
#include <QStringList>
#include <QDebug>
#include <QFont>
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QSettings settings(QString::fromLocal8Bit(argv[1]), QSettings::IniFormat);
  QStringList expected;
  for (int i=2;i<argc;++i) expected << QString::fromLocal8Bit(argv[i]);
  bool fonts = settings.value("Fonts/general").toString() == QString::fromUtf8(qgetenv("EXPECTED_SANS"))
    && settings.value("Fonts/fixed").toString() == QString::fromUtf8(qgetenv("EXPECTED_MONO"));
  QFont general, fixed;
  fonts = fonts && general.fromString(settings.value("Fonts/general").toString()) && fixed.fromString(settings.value("Fonts/fixed").toString())
    && general.weight() == QFont::Normal && fixed.weight() == QFont::Normal && general.pointSize() == 11 && fixed.pointSize() == 11;
  bool lists = settings.value("Interface/stylesheets").toStringList() == expected;
  if (!fonts || !lists) qWarning() << "fonts valid:" << fonts << "stylesheets:" << settings.value("Interface/stylesheets").toStringList() << "expected:" << expected;
  return fonts && lists ? 0 : 1;
}
CPP
$CXX -std=c++17 qt-settings.cpp -o qt-settings $(pkg-config --cflags --libs Qt6Gui)
./qt-settings "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$PRODUCTION_CONFIG_HOME/qt6ct/qss/one-dark.qss"
cat > "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" <<'CONF'
[Appearance]
icon_theme=Papirus-Dark
style=Fusion
[Fonts]
general=Noto Sans CJK SC,11,-1,5,400,0,0,0,0,0
fixed=JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0
[Interface]
stylesheets="/custom/with,comma.qss", /custom/other.qss
[Unknown]
keep=untouched
CONF
source "$QT_MIGRATION"
./qt-settings "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "/custom/with,comma.qss" /custom/other.qss "$XDG_CONFIG_HOME/qt6ct/qss/one-dark.qss"
grep -Fx "icon_theme=$ICON_NAME" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
grep -Fx 'keep=untouched' "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/migrated.conf"
source "$QT_MIGRATION"
cmp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/migrated.conf"

# Preserve unsupported, valid QSettings escapes instead of rewriting paths.
python3 - "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/seed.conf" <<'PY_ESCAPES'
import pathlib, re, sys
path=pathlib.Path(sys.argv[1])
text=pathlib.Path(sys.argv[2]).read_text()
text=re.sub(r"^stylesheets=.*$", lambda _: r"stylesheets=/custom/a\x20name.qss, @@myfile.qss", text, flags=re.M)
path.write_text(text)
PY_ESCAPES
cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/escaped.conf"
source "$QT_MIGRATION"
cmp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/escaped.conf"
./qt-settings "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "/custom/a name.qss" "@myfile.qss"
# CRLF and custom GUI choices survive an actual missing-reference migration.
python3 - "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/seed.conf" <<'PY_CRLF'
import os, pathlib, re, sys
text=pathlib.Path(sys.argv[2]).read_text().replace('style=Fusion','style=UserStyle').replace('icon_theme='+os.environ['ICON_NAME'],'icon_theme=UserIcons')
text=re.sub(r"^stylesheets=.*$", 'stylesheets="/custom/with,comma.qss", /custom/other.qss', text, flags=re.M)
pathlib.Path(sys.argv[1]).write_bytes(text.replace('\n','\r\n').encode())
PY_CRLF
source "$QT_MIGRATION"
./qt-settings "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "/custom/with,comma.qss" /custom/other.qss "$XDG_CONFIG_HOME/qt6ct/qss/one-dark.qss"
python3 - "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" <<'PY_VERIFY'
import pathlib,sys
data=pathlib.Path(sys.argv[1]).read_bytes()
assert data.count(b'\r\n') == data.count(b'\n')
assert b'icon_theme=UserIcons\r\n' in data and b'style=UserStyle\r\n' in data
PY_VERIFY
cp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/crlf.conf"
source "$QT_MIGRATION"
cmp "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$out/qt6ct/crlf.conf"
# Neither seed nor migration may write through a file or parent symlink.
mv "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf" "$TMPDIR/protected.conf"
cp "$TMPDIR/protected.conf" "$TMPDIR/unchanged.conf"
ln -s "$TMPDIR/protected.conf" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
source "$QT_SEED"
source "$QT_MIGRATION"
cmp "$TMPDIR/protected.conf" "$TMPDIR/unchanged.conf"
rm "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
mv "$TMPDIR/protected.conf" "$XDG_CONFIG_HOME/qt6ct/qt6ct.conf"
mv "$XDG_CONFIG_HOME/qt6ct" "$XDG_CONFIG_HOME/qt6ct-real"
ln -s qt6ct-real "$XDG_CONFIG_HOME/qt6ct"
source "$QT_SEED"
source "$QT_MIGRATION"
cmp "$XDG_CONFIG_HOME/qt6ct-real/qt6ct.conf" "$TMPDIR/unchanged.conf"
# A missing target proves that seed itself refuses a symlinked parent.
mv "$XDG_CONFIG_HOME/qt6ct-real/qt6ct.conf" "$TMPDIR/missing-target.conf"
source "$QT_SEED"
test ! -e "$XDG_CONFIG_HOME/qt6ct-real/qt6ct.conf"
cmp "$TMPDIR/missing-target.conf" "$TMPDIR/unchanged.conf"
