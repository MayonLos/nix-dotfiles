//! Small, secret-free client for the Mihomo external controller API.
//!
//! The controller is reached only through the caller-provided Unix socket. We
//! intentionally do not add an Authorization header: Verge's Unix socket is
//! already the supported local boundary and its API secret must stay private.

use std::{collections::BTreeMap, path::PathBuf, time::Duration};

use reqwest::{Client as HttpClient, Method, Response, Url};
use serde::Deserialize;

/// Safe error categories for UI display. Response bodies and request URLs are
/// never included, so API errors cannot accidentally reveal subscription data.
#[derive(Debug)]
pub enum ApiError {
    Transport,
    InvalidResponse,
    Rejected,
    InvalidEndpoint,
}

impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Transport => "Mihomo controller is unavailable",
            Self::InvalidResponse => "Mihomo returned an invalid response",
            Self::Rejected => "Mihomo rejected the operation",
            Self::InvalidEndpoint => "could not construct controller endpoint",
        })
    }
}

impl std::error::Error for ApiError {}

/// Parsed proxy row from `/proxies`. Unknown fields are ignored by serde.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct Proxy {
    #[serde(default)]
    pub name: String,
    #[serde(rename = "type", default)]
    pub kind: String,
    #[serde(default)]
    pub now: Option<String>,
    #[serde(default)]
    pub all: Vec<String>,
    #[serde(default)]
    pub history: Vec<DelaySample>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct DelaySample {
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub delay: u64,
}

/// Relevant fields from `/configs`.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct RuntimeConfig {
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub tun: TunConfig,
    #[serde(rename = "mixed-port", default)]
    pub mixed_port: Option<u16>,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct TunConfig {
    #[serde(default)]
    pub enable: bool,
}

/// A single active connection from `/connections`.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct Connection {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub metadata: ConnectionMetadata,
    #[serde(default)]
    pub rule: String,
    #[serde(default, rename = "rulePayload")]
    pub rule_payload: String,
    #[serde(default)]
    pub chains: Vec<String>,
    #[serde(default)]
    pub upload: u64,
    #[serde(default)]
    pub download: u64,
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
pub struct ConnectionMetadata {
    #[serde(default)]
    pub network: String,
    #[serde(default)]
    pub host: String,
    #[serde(default, rename = "destinationIP")]
    pub destination_ip: String,
    #[serde(default, rename = "destinationPort")]
    pub destination_port: String,
    #[serde(default, rename = "sourceIP")]
    pub source_ip: String,
    #[serde(default, rename = "sourcePort")]
    pub source_port: String,
}

#[derive(Debug, Deserialize)]
struct ProxyResponse {
    #[serde(default)]
    proxies: BTreeMap<String, Proxy>,
}

#[derive(Debug, Deserialize)]
struct ConnectionsResponse {
    #[serde(default, deserialize_with = "null_connections")]
    connections: Vec<Connection>,
}

// Mihomo encodes its nil slice as JSON null when no connection is active.
fn null_connections<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Vec<Connection>, D::Error> {
    Ok(Option::<Vec<Connection>>::deserialize(deserializer)?.unwrap_or_default())
}

/// Mihomo API client attached to one Unix domain socket.
#[derive(Clone, Debug)]
pub struct Client {
    http: HttpClient,
    base: Url,
}

impl Client {
    /// Build a client that can communicate only over `socket`.
    pub fn new(socket: PathBuf) -> Result<Self, reqwest::Error> {
        let http = HttpClient::builder()
            .unix_socket(socket)
            .no_proxy()
            .connect_timeout(Duration::from_secs(3))
            .read_timeout(Duration::from_secs(8))
            .build()?;
        // reqwest's Unix socket transport ignores the host, but requires a
        // syntactically valid HTTP origin to construct requests.
        let base = Url::parse("http://mihomo/").expect("constant URL is valid");
        Ok(Self { http, base })
    }

    fn endpoint(&self, segments: &[&str]) -> Result<Url, ApiError> {
        let mut url = self.base.clone();
        {
            let mut path = url
                .path_segments_mut()
                .map_err(|_| ApiError::InvalidEndpoint)?;
            path.clear();
            for segment in segments {
                path.push(segment);
            }
        }
        Ok(url)
    }

    async fn json<T: for<'de> Deserialize<'de>>(
        &self,
        method: Method,
        segments: &[&str],
        body: Option<serde_json::Value>,
    ) -> Result<T, ApiError> {
        let url = self.endpoint(segments)?;
        let mut request = self.http.request(method, url);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request
            .timeout(Duration::from_secs(8))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if !response.status().is_success() {
            return Err(ApiError::Rejected);
        }
        response.json().await.map_err(|_| ApiError::InvalidResponse)
    }

    async fn empty(
        &self,
        method: Method,
        segments: &[&str],
        body: Option<serde_json::Value>,
    ) -> Result<(), ApiError> {
        let url = self.endpoint(segments)?;
        let mut request = self.http.request(method, url);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request
            .timeout(Duration::from_secs(8))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(ApiError::Rejected)
        }
    }

    /// Return proxy groups and proxy nodes keyed by their API names.
    pub async fn proxies(&self) -> Result<BTreeMap<String, Proxy>, ApiError> {
        Ok(self
            .json::<ProxyResponse>(Method::GET, &["proxies"], None)
            .await?
            .proxies)
    }

    /// Return the current mode, TUN flag, and mixed port.
    pub async fn configs(&self) -> Result<RuntimeConfig, ApiError> {
        self.json(Method::GET, &["configs"], None).await
    }

    /// Return Mihomo version information as a display-ready string.
    pub async fn version(&self) -> Result<String, ApiError> {
        #[derive(Deserialize)]
        struct Version {
            #[serde(default)]
            version: String,
            #[serde(default)]
            meta: bool,
        }
        let version: Version = self.json(Method::GET, &["version"], None).await?;
        Ok(format!(
            "{}{}",
            if version.meta { "Meta " } else { "" },
            version.version
        ))
    }

    /// Read the complete current connections snapshot.
    pub async fn connections(&self) -> Result<Vec<Connection>, ApiError> {
        Ok(self
            .json::<ConnectionsResponse>(Method::GET, &["connections"], None)
            .await?
            .connections)
    }

    /// Select `node` in the proxy group `group`.
    pub async fn select(&self, group: &str, node: &str) -> Result<(), ApiError> {
        let url = self.endpoint(&["proxies", group])?;
        let response = self
            .http
            .put(url)
            .timeout(Duration::from_secs(8))
            .json(&serde_json::json!({ "name": node }))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(ApiError::Rejected)
        }
    }

    /// Change global routing mode (`rule`, `global`, or `direct`).
    pub async fn set_mode(&self, mode: &str) -> Result<(), ApiError> {
        self.empty(
            Method::PATCH,
            &["configs"],
            Some(serde_json::json!({ "mode": mode })),
        )
        .await
    }

    /// Probe one proxy and return its measured delay in milliseconds.
    pub async fn delay(
        &self,
        proxy: &str,
        test_url: &str,
        timeout_ms: u64,
    ) -> Result<u64, ApiError> {
        let url = Url::parse(test_url).map_err(|_| ApiError::InvalidEndpoint)?;
        let mut endpoint = self.endpoint(&["proxies", proxy, "delay"])?;
        endpoint
            .query_pairs_mut()
            .append_pair("url", url.as_str())
            .append_pair("timeout", &timeout_ms.to_string());
        #[derive(Deserialize)]
        struct Delay {
            delay: u64,
        }
        let response = self
            .http
            .get(endpoint)
            .timeout(Duration::from_secs(8))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if !response.status().is_success() {
            return Err(ApiError::Rejected);
        }
        response
            .json::<Delay>()
            .await
            .map(|delay| delay.delay)
            .map_err(|_| ApiError::InvalidResponse)
    }

    /// Close an active connection by its controller ID.
    pub async fn close(&self, id: &str) -> Result<(), ApiError> {
        self.empty(Method::DELETE, &["connections", id], None).await
    }

    /// Begin the `/traffic` WebSocket-compatible streaming HTTP response.
    /// The caller may parse each newline-delimited JSON frame from `bytes_stream`.
    pub async fn traffic_response(&self) -> Result<Response, ApiError> {
        let url = self.endpoint(&["traffic"])?;
        let response = self
            .http
            .get(url)
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if response.status().is_success() {
            Ok(response)
        } else {
            Err(ApiError::Rejected)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_proxy_groups_and_nodes() {
        let parsed: ProxyResponse = serde_json::from_str(
            r#"{"proxies":{"Auto":{"name":"Auto","type":"URLTest","now":"Node A","all":["Node A","DIRECT"],"unknown":true},"DIRECT":{"name":"DIRECT","type":"Direct"}}}"#,
        )
        .unwrap();
        assert_eq!(parsed.proxies["Auto"].kind, "URLTest");
        assert_eq!(parsed.proxies["Auto"].now.as_deref(), Some("Node A"));
        assert_eq!(parsed.proxies["DIRECT"].all, Vec::<String>::new());
    }

    #[test]
    fn parses_configs_and_connections_with_optional_fields() {
        let config: RuntimeConfig = serde_json::from_str(
            r#"{"mode":"global","tun":{"enable":true,"stack":"mixed"},"mixed-port":7890}"#,
        )
        .unwrap();
        assert_eq!(config.mode, "global");
        assert!(config.tun.enable);
        assert_eq!(config.mixed_port, Some(7890));

        assert!(
            serde_json::from_str::<ConnectionsResponse>(r#"{"connections":null}"#)
                .unwrap()
                .connections
                .is_empty()
        );
        let parsed: ConnectionsResponse = serde_json::from_str(
            r#"{"connections":[{"id":"abc","metadata":{"network":"tcp","host":"example.com","destinationIP":"1.2.3.4","destinationPort":"443"},"rule":"MATCH","rulePayload":"MATCH","chains":["DIRECT"],"upload":12,"download":34,"new-field":1}],"memory":0}"#,
        )
        .unwrap();
        assert_eq!(parsed.connections[0].metadata.host, "example.com");
        assert_eq!(parsed.connections[0].download, 34);
    }

    #[test]
    fn encodes_untrusted_api_path_segments() {
        let client = Client {
            // The client is not used in these URL-construction tests.
            http: HttpClient::new(),
            base: Url::parse("http://mihomo/").unwrap(),
        };
        let endpoint = client
            .endpoint(&["proxies", "Group / 测试?", "delay"])
            .unwrap();
        assert_eq!(
            endpoint.path(),
            "/proxies/Group%20%2F%20%E6%B5%8B%E8%AF%95%3F/delay"
        );
    }
}
