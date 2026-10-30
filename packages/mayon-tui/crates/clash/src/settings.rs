//! Optional user-owned preferences. No writer and no service configuration.
use serde::Deserialize;
use std::path::Path;
#[derive(Clone, Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Settings {
    // Read old preference files without making the retired backend selectable.
    #[serde(default, rename = "backend")]
    _legacy_backend: Option<String>,
    pub test_url: String,
    pub timeout_ms: u64,
    /// Limits client-side batch probes; Mihomo owns group/provider concurrency.
    pub concurrency: usize,
    pub default_sort: String,
    pub default_page: usize,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            _legacy_backend: None,
            test_url: "https://www.gstatic.com/generate_204".into(),
            timeout_ms: 5000,
            concurrency: 4,
            default_sort: "default".into(),
            default_page: 1,
        }
    }
}
impl Settings {
    pub fn load(path: &Path) -> Result<Self, &'static str> {
        let text = match std::fs::read_to_string(path) {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(_) => return Err("无法读取 Clash TUI 配置"),
        };
        let value: Self = toml::from_str(&text).map_err(|_| "Clash TUI 配置格式无效")?;
        value.validate()?;
        Ok(value)
    }
    pub fn validate(&self) -> Result<(), &'static str> {
        if !(100..=30000).contains(&self.timeout_ms)
            || !(1..=32).contains(&self.concurrency)
            || !(1..=7).contains(&self.default_page)
            || !matches!(self.default_sort.as_str(), "default" | "delay" | "name")
        {
            return Err(
                "配置范围无效：超时 100–30000ms，并发 1–32，首页 1–7，排序 default/delay/name",
            );
        }
        if !reqwest::Url::parse(&self.test_url)
            .is_ok_and(|u| matches!(u.scheme(), "http" | "https"))
        {
            return Err("测速地址必须为 http(s) URL");
        }
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn preferences_validate_and_default() {
        let s: Settings =
            toml::from_str("backend = 'verge'\nconcurrency = 2\ndefault_sort = 'delay'").unwrap();
        assert!(s.validate().is_ok());
        assert_eq!(s.default_page, 1);
        let mut bad = s;
        bad.timeout_ms = 32768;
        assert!(bad.validate().is_err());
        assert!(toml::from_str::<Settings>("secret='x'").is_err());
    }
}
