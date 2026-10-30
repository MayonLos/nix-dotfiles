//! Read-only models for Clash Verge Rev profile metadata.
//!
//! Verge owns `profiles.yaml`; this module only parses a caller-supplied snapshot.
//! Never include a profile URL in diagnostic messages because it may contain credentials.

use chrono::{DateTime, Local, TimeZone, Utc};
use reqwest::Url;
use serde::{Deserialize, Serialize};

/// The subset of Verge's `profiles.yaml` needed by the TUI.
#[derive(Clone, Deserialize, Default)]
pub struct ProfileStore {
    pub current: Option<String>,
    #[serde(default, deserialize_with = "deserialize_nullable_items")]
    pub items: Vec<ProfileItem>,
}

fn deserialize_nullable_items<'de, D>(deserializer: D) -> Result<Vec<ProfileItem>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Ok(Option::<Vec<ProfileItem>>::deserialize(deserializer)?.unwrap_or_default())
}

impl ProfileStore {
    /// Parse a snapshot read by the caller. This function never writes the source file.
    pub fn from_yaml(yaml: &str) -> Result<Self, serde_yaml::Error> {
        serde_yaml::from_str(yaml)
    }

    #[cfg(test)]
    fn current_item(&self) -> Option<&ProfileItem> {
        let current = self.current.as_deref()?;
        self.items
            .iter()
            .find(|item| item.uid.as_deref() == Some(current))
    }
}

/// Verge profile entry (unknown fields are intentionally ignored).
#[derive(Clone, Deserialize, Default)]
pub struct ProfileItem {
    pub uid: Option<String>,
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub name: Option<String>,
    /// Sensitive: may contain embedded credentials. Do not log or render this value.
    pub url: Option<String>,
    /// Unix timestamp in seconds, as stored by Verge.
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

/// Usage values in Verge's `extra` field and Mihomo's `subscription-userinfo` header.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, Default, PartialEq, Eq)]
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

    /// Verge/Mihomo use a Unix timestamp in seconds; zero means no expiry.
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

/// Construct Verge's supported `clash://install-config` deep link.
///
/// The returned URL contains the subscription URL (potentially with credentials).
/// Treat it as a secret: do not log it, include it in errors, or persist it.
pub fn verge_import_link(subscription: &Url) -> Url {
    let mut link = Url::parse("clash://install-config").expect("static deep link URL is valid");
    {
        let mut query = link.query_pairs_mut();
        query.append_pair("url", subscription.as_str());
    }
    link
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_profile_store_and_usage() {
        let store = ProfileStore::from_yaml(
            "current: sub-a\nitems:\n  - uid: sub-a\n    type: remote\n    name: Demo\n    url: https://example.invalid/sub?token=secret\n    updated: 1735689600\n    extra:\n      upload: 200\n      download: 300\n      total: 1000\n      expire: 1893456000\n  - uid: merge-1\n    type: merge\n    name: Merge\n",
        )
        .unwrap();
        assert_eq!(store.items.len(), 2);
        assert_eq!(
            store.current_item().unwrap().kind.as_deref(),
            Some("remote")
        );
        assert!(ProfileStore::from_yaml("current: null\nitems: null\n")
            .unwrap()
            .items
            .is_empty());
        let usage = store.current_item().unwrap().extra.unwrap();
        assert_eq!(usage.used_bytes(), 500);
        assert_eq!(usage.remaining_bytes(), Some(500));
        assert_eq!(usage.progress(), Some(0.5));
        assert!(store.current_item().unwrap().updated_at().is_some());
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

    #[test]
    fn builds_encoded_verge_deep_link() {
        let subscription = Url::parse("https://example.invalid/sub?token=keep&x=1").unwrap();
        let link = verge_import_link(&subscription);
        assert_eq!(link.scheme(), "clash");
        assert_eq!(link.host_str(), Some("install-config"));
        let pairs: Vec<_> = link.query_pairs().collect();
        assert_eq!(pairs[0].0, "url");
        assert_eq!(pairs[0].1, subscription.as_str());
        assert_eq!(pairs.len(), 1); // v2.4.7 cannot reliably forward an optional name.
    }
}
