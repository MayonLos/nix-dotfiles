//! 【界面主题】【菜单配色】贴图和正文右键菜单共用原版明暗令牌

use super::{Mode, Rgba};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Palette {
    pub accent: Rgba,
    pub background: Rgba,
    pub border: Rgba,
    pub checked_background: Rgba,
    pub danger_hover_background: Rgba,
    pub danger_hover_text: Rgba,
    pub danger_text: Rgba,
    pub disabled_text: Rgba,
    pub hover_background: Rgba,
    pub hover_text: Rgba,
    pub secondary_text: Rgba,
    pub separator: Rgba,
    pub text: Rgba,
}

impl Palette {
    /// 【界面主题】【当前菜单】返回当前进程菜单配色，无参数
    pub fn current() -> Self {
        Self::new(Mode::current())
    }

    /// 【界面主题】【菜单令牌】按 mode 返回原版配色，不修改菜单几何
    pub fn new(mode: Mode) -> Self {
        match mode {
            Mode::System => Self::new(mode.resolved()),
            Mode::Light => Self {
                accent: Rgba(13, 148, 136, 255),
                background: Rgba(255, 255, 255, 250),
                border: Rgba(15, 23, 42, 26),
                checked_background: Rgba(13, 148, 136, 30),
                danger_hover_background: Rgba(254, 226, 226, 255),
                danger_hover_text: Rgba(185, 28, 28, 255),
                danger_text: Rgba(220, 38, 38, 255),
                disabled_text: Rgba(160, 174, 192, 255),
                hover_background: Rgba(15, 23, 42, 14),
                hover_text: Rgba(15, 23, 42, 255),
                secondary_text: Rgba(100, 116, 139, 255),
                separator: Rgba(15, 23, 42, 20),
                text: Rgba(31, 41, 55, 255),
            },
            Mode::Dark => Self {
                accent: Rgba(97, 175, 239, 255),
                background: Rgba(30, 34, 40, 248),
                border: Rgba(92, 99, 112, 120),
                checked_background: Rgba(97, 175, 239, 40),
                danger_hover_background: Rgba(224, 108, 117, 60),
                danger_hover_text: Rgba(235, 155, 160, 255),
                danger_text: Rgba(224, 108, 117, 255),
                disabled_text: Rgba(130, 138, 149, 255),
                hover_background: Rgba(97, 175, 239, 45),
                hover_text: Rgba(215, 218, 224, 255),
                secondary_text: Rgba(171, 178, 191, 255),
                separator: Rgba(92, 99, 112, 90),
                text: Rgba(215, 218, 224, 255),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    /// 【主题令牌测试】【调色板对照】浅色仍对照原版 Qt 函数输出；暗色为仓库 One Dark
    ///（tests/fixtures/qt-theme.json 的 dark 段同步更新），所有角色必须一致
    #[test]
    fn both_palettes_match_the_actual_qt_functions() {
        let reference: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/fixtures/qt-theme.json")).unwrap();
        for mode in [Mode::Light, Mode::Dark] {
            let palette = Palette::new(mode);
            let expected = &reference[mode.name()]["menu"];
            for (name, color) in [
                ("accent", palette.accent),
                ("background", palette.background),
                ("border", palette.border),
                ("checked_background", palette.checked_background),
                ("danger_hover_background", palette.danger_hover_background),
                ("danger_hover_text", palette.danger_hover_text),
                ("danger_text", palette.danger_text),
                ("disabled_text", palette.disabled_text),
                ("hover_background", palette.hover_background),
                ("hover_text", palette.hover_text),
                ("secondary_text", palette.secondary_text),
                ("separator", palette.separator),
                ("text", palette.text),
            ] {
                assert_eq!(
                    serde_json::json!([color.0, color.1, color.2, color.3]),
                    expected[name],
                    "{}: {name}",
                    mode.name()
                );
            }
        }
    }
}
