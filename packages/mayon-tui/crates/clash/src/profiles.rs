//! Subscription metadata and usage values displayed by the Clash TUI.
//! Never include a subscription URL in diagnostics because it may contain credentials.

use chrono::{DateTime, Local, TimeZone, Utc};
use serde::Serialize;

#[derive(Clone, Default)]
pub struct ProfileStore {
    pub current: Option<String>,
    pub items: Vec<ProfileItem>,
}

#[derive(Clone, Default)]
pub struct ProfileItem {
    pub uid: Option<String>,
    pub name: Option<String>,
    pub url: Option<String>,
    pub updated: Option<i64>,
    pub extra: Option<Usage>,
}

impl ProfileItem {
    pub fn updated_at(&self) -> Option<DateTime<Local>> {
        self.updated
            .and_then(|timestamp| Utc.timestamp_opt(timestamp, 0).single())
            .map(|time| time.with_timezone(&Local))
    }
}

/// Usage values from a subscription provider usage header.
#[derive(Debug, Clone, Copy, serde::Deserialize, Serialize, Default, PartialEq, Eq)]
pub struct Usage {
    #[serde(default)]
    pub upload: u64,
    #[serde(default)]
    pub download: u64,
    #[serde(default)]
    pub total: u64,
    #[serde(default)]
    pub expire: u64,
}

impl Usage {
    /// Parse `subscription-userinfo: upload=...; download=...; total=...; expire=...`.
    /// Unknown keys are ignored, and malformed or overflowing numbers return an error.
    pub fn from_header(header: &str) -> Result<Self, HeaderParseError> {
        let mut usage = Self::default();
        let mut recognized = false;
        for field in header
            .split(';')
            .map(str::trim)
            .filter(|field| !field.is_empty())
        {
            let (key, value) = field
                .split_once('=')
                .ok_or(HeaderParseError::InvalidField)?;
            match key.trim().to_ascii_lowercase().as_str() {
                "upload" => {
                    usage.upload = value
                        .trim()
                        .parse()
                        .map_err(|_| HeaderParseError::InvalidNumber)?;
                    recognized = true;
                }
                "download" => {
                    usage.download = value
                        .trim()
                        .parse()
                        .map_err(|_| HeaderParseError::InvalidNumber)?;
                    recognized = true;
                }
                "total" => {
                    usage.total = value
                        .trim()
                        .parse()
                        .map_err(|_| HeaderParseError::InvalidNumber)?;
                    recognized = true;
                }
                "expire" => {
                    usage.expire = value
                        .trim()
                        .parse()
                        .map_err(|_| HeaderParseError::InvalidNumber)?;
                    recognized = true;
                }
                _ => {}
            }
        }
        if !recognized {
            return Err(HeaderParseError::NoRecognizedFields);
        }
        Ok(usage)
    }

    pub fn used_bytes(self) -> u64 {
        self.upload.saturating_add(self.download)
    }

    pub fn remaining_bytes(self) -> Option<u64> {
        (self.total > 0).then(|| self.total.saturating_sub(self.used_bytes()))
    }

    /// Fraction from 0.0 to 1.0. Unknown/zero quota has no progress value.
    pub fn progress(self) -> Option<f64> {
        (self.total > 0).then(|| (self.used_bytes() as f64 / self.total as f64).clamp(0.0, 1.0))
    }

    /// Providers use a Unix timestamp in seconds; zero means no expiry.
    pub fn expires_at(self) -> Option<DateTime<Local>> {
        let timestamp = i64::try_from(self.expire).ok()?;
        (timestamp > 0)
            .then(|| Utc.timestamp_opt(timestamp, 0).single())
            .flatten()
            .map(|time| time.with_timezone(&Local))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeaderParseError {
    InvalidField,
    InvalidNumber,
    NoRecognizedFields,
}

impl std::fmt::Display for HeaderParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidField => f.write_str("subscription usage field must use key=value"),
            Self::InvalidNumber => {
                f.write_str("subscription usage value must be a non-negative integer")
            }
            Self::NoRecognizedFields => {
                f.write_str("subscription usage header has no recognized fields")
            }
        }
    }
}

impl std::error::Error for HeaderParseError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_subscription_usage() {
        let usage = Usage {
            upload: 200,
            download: 300,
            total: 1000,
            expire: 1893456000,
        };
        assert_eq!(usage.used_bytes(), 500);
        assert_eq!(usage.remaining_bytes(), Some(500));
        assert_eq!(usage.progress(), Some(0.5));
        assert!(usage.expires_at().is_some());
    }

    #[test]
    fn parses_subscription_header_with_unknown_fields_and_clamps_usage() {
        let usage = Usage::from_header(
            "upload=5; download=20; total=10; expire=1893456000; source=example",
        )
        .unwrap();
        assert_eq!(usage.used_bytes(), 25);
        assert_eq!(usage.remaining_bytes(), Some(0));
        assert_eq!(usage.progress(), Some(1.0));
        assert!(Usage::from_header("upload=nope").is_err());
        assert!(Usage::from_header("upload").is_err());
        assert!(Usage::from_header("").is_err());
        assert!(Usage::from_header("source=example").is_err());
        assert_eq!(Usage::default().remaining_bytes(), None);
        assert_eq!(Usage::default().expires_at(), None);
        assert_eq!(
            Usage {
                expire: u64::MAX,
                ..Usage::default()
            }
            .expires_at(),
            None
        );
    }
}
