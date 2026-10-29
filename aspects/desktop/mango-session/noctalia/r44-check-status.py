"""Fail closed when the locked native status rendering changes."""

from pathlib import Path


power = Path("src/dbus/upower/upower_service.cpp").read_text()
glyph = power.split("const char* batteryGlyphName(", 1)[1].split("const char* batteryDeviceGlyphName(", 1)[0]
assert 'return "battery-plugged"' not in glyph
assert glyph.count('return "battery-charging"') == 2
assert "BatteryState::FullyCharged || state == BatteryState::PendingCharge" in glyph
for level in range(5):
    assert f'return "battery-{level}"' in glyph

bar = Path("src/shell/bar/widgets")
battery = (bar / "battery_widget.cpp").read_text()
assert "m_glyph->setGlyph(batteryGlyphName(s.percentage, s.state))" in battery
# Keep upstream low-discharge colour semantics; AC must never trigger warning.
assert "m_warningThreshold > 0 && pct <= m_warningThreshold && !isPluggedIn" in battery
assert "isWarning ? m_warningColor : widgetIconColorOr" in battery
network = (bar / "network_widget.cpp").read_text()
bluetooth = (bar / "bluetooth_widget.cpp").read_text()
assert "m_glyph->setColor(s.connected || s.resolving" in network
assert "m_glyph->setColor(s.powered && hasConnectedDevice" in bluetooth
for source in (network, bluetooth):
    assert "? widgetIconColorOr(colorSpecFromRole(ColorRole::OnSurface))" in source
    assert ": colorSpecFromRole(ColorRole::OnSurfaceVariant)" in source
    assert "m_glyph->setGlyphSize(Style::baseGlyphSize * m_contentScale)" in source
print("R44 native battery glyph, warning and device foreground contracts passed")

# hicolor's standard index can omit a package's 1024-only application icon.
resolver = Path("src/system/icon_resolver.cpp").read_text()
assert 'themeName == "hicolor" && pathIsDirectory(largeApps)' in resolver
assert '.path = largeApps, .size = 1024' in resolver
host = Path("src/scripting/luau_host.cpp").read_text()
assert 'std::string_view(appId, len).starts_with("/")' in host
