//! Selection never sends a controller request. Explicit socket overrides are for isolation.
use serde::Deserialize;
use std::{os::unix::net::UnixStream, path::Path};
#[derive(Clone, Copy, Default, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Preference {
    #[default]
    Auto,
    Native,
    Verge,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    Native,
    Verge,
}
impl Backend {
    pub fn detect(preference: Preference, verge: &Path) -> Self {
        match preference {
            Preference::Native => Self::Native,
            Preference::Verge => Self::Verge,
            Preference::Auto if UnixStream::connect(verge).is_ok() => Self::Verge,
            Preference::Auto => Self::Native,
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Native => "native",
            Self::Verge => "Verge",
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn selection_only_checks_live_socket() {
        let p = std::env::temp_dir().join(format!("mayon-backend-{}", std::process::id()));
        assert_eq!(Backend::detect(Preference::Auto, &p), Backend::Native);
        let l = std::os::unix::net::UnixListener::bind(&p).unwrap();
        assert_eq!(Backend::detect(Preference::Auto, &p), Backend::Verge);
        assert_eq!(Backend::detect(Preference::Native, &p), Backend::Native);
        drop(l);
        std::fs::remove_file(p).unwrap();
    }
}
