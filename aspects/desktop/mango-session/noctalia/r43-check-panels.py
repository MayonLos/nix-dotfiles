#!/usr/bin/env python3
"""Fail at postPatch when the locked Noctalia panel adaptation drifts."""
from pathlib import Path


def source(path):
    return Path('src', path).read_text()


ranges = source('config/schema/ranges.h')
assert 'kControlCenterWidthRange{348, 1200, 10}' in ranges
assert 'kLauncherWidthRange{520, 1100, 10}' in ranges

types = source('config/config_types.cpp')
assert 'case PanelTransparencyMode::Soft:\n    return 0.80F;' in types
scene = source('shell/settings/settings_window_scene.cpp')
assert 'cfg.shell.settingsWindowTranslucent ? 0.8F : 1.0F' in scene
home = source('shell/control_center/tabs/home_tab.cpp')
assert 'kHomeShortcutGridColumns = 2' in home
assert 'std::size_t{7}' in home
assert 'if (i < 2)' in home and 'functionRows->addChild(std::move(btn))' in home
assert '.trackHeight = 3.0F * scale' in home
assert 'const float artSize = 40.0F * scale' in home
assert 'if (button.direction() == FlexDirection::Horizontal)' in home
assert 'pad.label->setFontSize(14.0F * s)' in home
assert 'pad.label->setFontSize(Style::fontSizeMini * s)' not in home
assert 'userCard->setParticipatesInLayout(false)' in home
assert 'dateTimeCard->setParticipatesInLayout(false)' in home
panel = source('shell/control_center/control_center_panel.cpp')
assert 'return fullSize * m_contentScale' in panel
assert 'std::max(600.0F, fullSize) * m_contentScale' in panel
manager = source('shell/panel/panel_manager.cpp')
assert 'if (panelId == "control-center") {' in manager
assert 'request.context = context;\n              request.sourceBarName = sourceBarName;\n              openPanel(panelId, request);' in manager
assert 'return 320.0F * m_contentScale' in panel
assert 'tabFromContext(context) == TabId::Calendar) return ControlCenterSidebarMode::None' in panel
assert 'fullSize * 0.85F' not in panel
calendar_tab = source('shell/control_center/tabs/calendar_tab.cpp')
assert 'auto tab = ui::column({' in calendar_tab
assert 'calendarArea->setSize(0.0F, 356.0F * scale)' in calendar_tab
assert 'return formatLocalTime("%-m月%-d日")' in calendar_tab
assert 'constexpr float kCalendarGridGap = 4.0F' in calendar_tab
calendar = source('ui/controls/calendar_view.cpp')
assert 'button->addChild(ui::box({' in calendar
assert '.borderWidth = 1.0F * options.scale' in calendar
assert 'outline.setHitTestVisible(false)' in calendar
assert 'day.normal.border = colorSpecFromRole(ColorRole::Primary)' not in calendar
assert 'button->setVariant(ButtonVariant::Primary)' not in calendar
notification = source('shell/notification/notification_toast.cpp')
assert 'constexpr float kMetaFontSize = 13.0F' in notification
assert 'constexpr float kSummaryFontSize = 14.0F' in notification
assert 'constexpr int kProgressHeight = 1' in notification
assert 'the accent sat on the card' in notification
osd = source('shell/osd/osd_overlay.cpp')
for literal in ['return 246.0F * s', 'return 46.0F * s', 'return 3.0F * s', 'return 18.0F * s']:
    assert literal in osd, literal
assert 'return (vertical ? 16.0F : 20.0F) * s' in osd
assert '.fontFeatures = vertical ? "" : "tnum"' in osd
assert 'std::max(36.0F * s, value->width())' in osd
assert 'iconCell = ui::row({' in osd
assert 'm_content.value.size() <= 4' in osd
assert 'progressTicks' not in osd
assert ': ColorRole::Primary;' not in osd
settings = source('shell/settings/settings_content.cpp')
assert 'makeLabel(title, 20.0F * scale, colorSpecFromRole(ColorRole::OnSurface), FontWeight::SemiBold)' in settings
sidebar = source('shell/settings/settings_sidebar.cpp')
assert 'styleCategoryButton(button, selected, scale)' in sidebar
assert '.width = 2.0F * scale' in sidebar and 'marker.setHitTestVisible(false)' in sidebar
wallpaper = source('shell/wallpaper/panel/wallpaper_panel.cpp')
assert '.columns = 3' in wallpaper
assert 'constexpr std::size_t columns = 3' in wallpaper
assert 'tileWidth * 0.62F - captionH' in wallpaper
assert 'viewport->setMaxHeight(viewportHeight)' in wallpaper
assert 'root->addChild(std::move(gridViewport))' in wallpaper
assert 'm_grid->parent()->setVisible(!loading)' in wallpaper
assert '2.0F * cellHeight + Style::spaceMd * scale' in wallpaper
tile = source('shell/wallpaper/panel/wallpaper_tile.cpp')
assert 'outlineWidth = 1.0F * m_contentScale' in tile
assert '(m_current ? "✓  " : "") + m_entry.name' in tile
assert 'return 1.04F' not in tile
print('R43: all six native panel adaptations verified')
