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
            Self::Transport => "内核控制接口不可用",
            Self::InvalidResponse => "内核响应格式无效",
            Self::Rejected => "内核拒绝操作，请检查当前配置",
            Self::InvalidEndpoint => "控制接口地址无效",
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
    #[serde(default)]
    pub start: String,
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
    #[serde(default)]
    pub process: String,
    #[serde(default, rename = "processPath")]
    pub process_path: String,
}

#[derive(Debug, Deserialize)]
struct ProxyResponse {
    #[serde(default)]
    proxies: BTreeMap<String, Proxy>,
}

#[derive(Clone, Debug, Default, Deserialize)]
pub struct ConnectionsResponse {
    #[serde(default, deserialize_with = "null_connections")]
    pub connections: Vec<Connection>,
    #[serde(default, rename = "uploadTotal")]
    pub upload_total: u64,
    #[serde(default, rename = "downloadTotal")]
    pub download_total: u64,
    #[serde(default)]
    pub memory: u64,
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
    socket: PathBuf,
}

impl Client {
    /// Build a client that can communicate only over `socket`.
    pub fn new(socket: PathBuf) -> Result<Self, reqwest::Error> {
        let http = HttpClient::builder()
            .unix_socket(socket.clone())
            .no_proxy()
            .connect_timeout(Duration::from_secs(3))
            .read_timeout(Duration::from_secs(8))
            .build()?;
        // reqwest's Unix socket transport ignores the host, but requires a
        // syntactically valid HTTP origin to construct requests.
        let base = Url::parse("http://mihomo/").expect("constant URL is valid");
        Ok(Self { http, base, socket })
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
            .timeout(Duration::from_secs(
                if segments.first() == Some(&"providers") {
                    180
                } else {
                    8
                },
            ))
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
            .timeout(Duration::from_millis(timeout_ms + 2000))
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

    pub async fn group_delay(
        &self,
        group: &str,
        url: &str,
        timeout: u64,
    ) -> Result<BTreeMap<String, u64>, ApiError> {
        let mut endpoint = self.endpoint(&["group", group, "delay"])?;
        endpoint
            .query_pairs_mut()
            .append_pair("url", url)
            .append_pair("timeout", &timeout.to_string());
        self.http
            .get(endpoint)
            .timeout(Duration::from_millis(timeout + 2000))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?
            .error_for_status()
            .map_err(|_| ApiError::Rejected)?
            .json()
            .await
            .map_err(|_| ApiError::InvalidResponse)
    }
    pub async fn providers(&self, rules: bool) -> Result<BTreeMap<String, Provider>, ApiError> {
        #[derive(Deserialize)]
        struct Providers {
            providers: BTreeMap<String, Provider>,
        }
        Ok(self
            .json::<Providers>(
                Method::GET,
                &["providers", if rules { "rules" } else { "proxies" }],
                None,
            )
            .await?
            .providers)
    }
    pub async fn rules(&self) -> Result<Vec<Rule>, ApiError> {
        #[derive(Deserialize)]
        struct Rules {
            rules: Vec<Rule>,
        }
        Ok(self
            .json::<Rules>(Method::GET, &["rules"], None)
            .await?
            .rules)
    }
    pub async fn update_provider(&self, name: &str, rules: bool) -> Result<(), ApiError> {
        self.empty(
            Method::PUT,
            &["providers", if rules { "rules" } else { "proxies" }, name],
            None,
        )
        .await
    }
    pub async fn healthcheck(&self, name: &str) -> Result<(), ApiError> {
        self.empty(
            Method::GET,
            &["providers", "proxies", name, "healthcheck"],
            None,
        )
        .await
    }
    pub async fn tool(&self, tool: usize) -> Result<(), ApiError> {
        let path: &[&str] = match tool {
            0 => &["cache", "fakeip", "flush"],
            1 => &["cache", "dns", "flush"],
            _ => &["configs", "geo"],
        };
        let response = self
            .http
            .post(self.endpoint(path)?)
            .timeout(Duration::from_secs(if tool == 2 { 180 } else { 8 }))
            .send()
            .await
            .map_err(|_| ApiError::Transport)?;
        if response.status().is_success() {
            Ok(())
        } else {
            Err(ApiError::Rejected)
        }
    }
    pub async fn close_all(&self) -> Result<(), ApiError> {
        self.empty(Method::DELETE, &["connections"], None).await
    }
    pub async fn connection_stream(
        &self,
    ) -> Result<tokio_tungstenite::WebSocketStream<tokio::net::UnixStream>, ApiError> {
        let stream = tokio::time::timeout(
            Duration::from_secs(3),
            tokio::net::UnixStream::connect(&self.socket),
        )
        .await
        .map_err(|_| ApiError::Transport)?
        .map_err(|_| ApiError::Transport)?;
        tokio_tungstenite::client_async("ws://mihomo/connections?interval=1000", stream)
            .await
            .map(|(ws, _)| ws)
            .map_err(|_| ApiError::Transport)
    }
    pub async fn logs_response(&self) -> Result<Response, ApiError> {
        self.http
            .get("http://mihomo/logs?level=debug")
            .send()
            .await
            .map_err(|_| ApiError::Transport)?
            .error_for_status()
            .map_err(|_| ApiError::Rejected)
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
            socket: "/unused".into(),
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

#[derive(Clone, Debug, Default, Deserialize)]
pub struct Provider {
    #[serde(default, rename = "vehicleType")]
    pub vehicle_type: String,
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub proxies: Vec<Proxy>,
    #[serde(default, rename = "updatedAt")]
    pub updated_at: String,
    #[serde(default, rename = "ruleCount")]
    pub rule_count: u64,
}
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Rule {
    #[serde(default, rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub payload: String,
    #[serde(default)]
    pub proxy: String,
    #[serde(default)]
    pub extra: Option<RuleExtra>,
}
#[derive(Clone, Debug, Default, Deserialize)]
pub struct RuleExtra {
    #[serde(default, rename = "hitCount")]
    pub hit_count: u64,
    #[serde(default, rename = "hitAt")]
    pub hit_at: String,
}
#[derive(Clone, Debug, Default, Deserialize)]
pub struct LogEntry {
    #[serde(default, rename = "type")]
    pub level: String,
    #[serde(default)]
    pub payload: String,
}
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Traffic {
    pub up: u64,
    pub down: u64,
    #[serde(default, rename = "upTotal")]
    pub up_total: u64,
    #[serde(default, rename = "downTotal")]
    pub down_total: u64,
}

#[cfg(test)]
mod transport_tests {
    use super::*;
    use futures_util::{SinkExt, StreamExt};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    fn socket() -> PathBuf {
        std::env::temp_dir().join(format!(
            "mayon-clash-test-{}-{}.sock",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ))
    }
    #[tokio::test]
    async fn route_methods_and_escaped_names_match_locked_core() {
        let path = socket();
        let listener = tokio::net::UnixListener::bind(&path).unwrap();
        let server = tokio::spawn(async move {
            let mut requests = vec![];
            for body in [r#"{"Node":42}"#, "", "", "", "", "", ""] {
                let (mut stream, _) = listener.accept().await.unwrap();
                let mut buffer = [0; 4096];
                let n = stream.read(&mut buffer).await.unwrap();
                requests.push(
                    String::from_utf8_lossy(&buffer[..n])
                        .lines()
                        .next()
                        .unwrap()
                        .to_string(),
                );
                stream
                    .write_all(
                        format!(
                            "HTTP/1.1 {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                            if body.is_empty() {
                                "204 No Content"
                            } else {
                                "200 OK"
                            },
                            body.len()
                        )
                        .as_bytes(),
                    )
                    .await
                    .unwrap();
            }
            requests
        });
        let client = Client::new(path.clone()).unwrap();
        assert_eq!(
            client
                .group_delay("Group / 测试?", "http://example.invalid/generate_204", 1000)
                .await
                .unwrap()["Node"],
            42
        );
        client.healthcheck("A/B").await.unwrap();
        client.update_provider("A/B", false).await.unwrap();
        client.update_provider("rules", true).await.unwrap();
        client.tool(0).await.unwrap();
        client.tool(1).await.unwrap();
        client.tool(2).await.unwrap();
        let requests = server.await.unwrap();
        assert!(requests[0].starts_with("GET /group/Group%20%2F%20%E6%B5%8B%E8%AF%95%3F/delay?"));
        assert!(requests[1].starts_with("GET /providers/proxies/A%2FB/healthcheck "));
        assert!(requests[2].starts_with("PUT /providers/proxies/A%2FB "));
        assert!(requests[3].starts_with("PUT /providers/rules/rules "));
        assert!(requests[4].starts_with("POST /cache/fakeip/flush "));
        assert!(requests[5].starts_with("POST /cache/dns/flush "));
        assert!(requests[6].starts_with("POST /configs/geo "));
        std::fs::remove_file(path).unwrap();
    }
    #[tokio::test]
    async fn connections_use_unix_websocket_frames() {
        let path = socket();
        let listener = tokio::net::UnixListener::bind(&path).unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut ws = tokio_tungstenite::accept_async(stream).await.unwrap();
            ws.send(tokio_tungstenite::tungstenite::Message::Text(
                r#"{"connections":null,"memory":1024,"uploadTotal":4,"downloadTotal":8}"#.into(),
            ))
            .await
            .unwrap();
            // Keep it open until the caller acknowledges the frame.
            let _ = ws.next().await;
        });
        let client = Client::new(path.clone()).unwrap();
        let mut ws = client.connection_stream().await.unwrap();
        let frame = ws.next().await.unwrap().unwrap();
        let snapshot: ConnectionsResponse = serde_json::from_str(frame.to_text().unwrap()).unwrap();
        assert!(snapshot.connections.is_empty());
        assert_eq!(snapshot.memory, 1024);
        assert_eq!(snapshot.download_total, 8);
        ws.close(None).await.unwrap();
        server.await.unwrap();
        std::fs::remove_file(path).unwrap();
    }
}
