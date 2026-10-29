use reqwest::{Client, Method, Response, StatusCode};
use serde::Deserialize;
use serde_json::Value;
use std::time::Duration;

#[derive(Clone)]
pub struct Engine {
    client: Client,
    pub host: String,
    pub can_stop_local_daemon: bool,
}
fn null_default_vec<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: serde::Deserializer<'de>,
    T: Deserialize<'de>,
{
    Ok(Option::<Vec<T>>::deserialize(deserializer)?.unwrap_or_default())
}
fn null_default_map<'de, D, K, V>(
    deserializer: D,
) -> Result<std::collections::HashMap<K, V>, D::Error>
where
    D: serde::Deserializer<'de>,
    K: Deserialize<'de> + Eq + std::hash::Hash,
    V: Deserialize<'de>,
{
    Ok(Option::<std::collections::HashMap<K, V>>::deserialize(deserializer)?.unwrap_or_default())
}

#[derive(Debug, Clone, Deserialize)]
pub struct Container {
    #[serde(rename = "Id")]
    pub id: String,
    #[serde(rename = "Names", default, deserialize_with = "null_default_vec")]
    pub names: Vec<String>,
    #[serde(rename = "Image", default)]
    pub image: String,
    #[serde(rename = "State", default)]
    pub state: String,
    #[serde(rename = "Status", default)]
    pub status: String,
    #[serde(rename = "Ports", default, deserialize_with = "null_default_vec")]
    pub ports: Vec<Port>,
    #[serde(rename = "Labels", default, deserialize_with = "null_default_map")]
    pub labels: std::collections::HashMap<String, String>,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Port {
    #[serde(rename = "IP")]
    pub ip: Option<String>,
    #[serde(rename = "PrivatePort")]
    pub private: u16,
    #[serde(rename = "PublicPort")]
    pub public: Option<u16>,
    #[serde(rename = "Type")]
    pub kind: String,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Image {
    #[serde(rename = "Id")]
    pub id: String,
    #[serde(rename = "RepoTags", default, deserialize_with = "null_default_vec")]
    pub tags: Vec<String>,
    #[serde(rename = "Size", default)]
    pub size: u64,
}
pub fn is_dangling(tags: &[String]) -> bool {
    tags.is_empty() || tags.iter().all(|tag| tag.starts_with("<none>"))
}
pub fn volume_delete_confirmed(presses: u8) -> bool {
    presses >= 2
}
pub fn reclaimable_build_cache(entries: &[BuildDisk]) -> u64 {
    entries
        .iter()
        .filter(|e| !e.in_use && !e.is_shared)
        .map(|e| e.size)
        .sum()
}
pub fn is_default_docker_socket(host: &str, runtime_dir: Option<&str>) -> bool {
    runtime_dir.is_some_and(|runtime| host == format!("unix://{runtime}/docker.sock"))
}
pub fn merge_volume_usage(volumes: &mut [Volume], disk: &Disk) {
    for volume in volumes {
        if volume.usage.is_none() {
            volume.usage = disk
                .volumes
                .iter()
                .find(|entry| entry.name == volume.name)
                .and_then(|entry| entry.usage.clone());
        }
    }
}
#[derive(Debug, Clone, Deserialize)]
pub struct Volume {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "UsageData")]
    pub usage: Option<UsageData>,
}
#[derive(Debug, Clone, Deserialize)]
pub struct UsageData {
    #[serde(rename = "Size", default)]
    pub size: i64,
    #[serde(rename = "RefCount", default)]
    pub refs: i64,
}
#[derive(Debug, Clone, Deserialize)]
pub struct DiskVolume {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "UsageData")]
    pub usage: Option<UsageData>,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Disk {
    #[serde(rename = "Images", default, deserialize_with = "null_default_vec")]
    pub images: Vec<ImageDisk>,
    #[serde(rename = "Containers", default, deserialize_with = "null_default_vec")]
    pub containers: Vec<Value>,
    #[serde(rename = "Volumes", default, deserialize_with = "null_default_vec")]
    pub volumes: Vec<DiskVolume>,
    #[serde(rename = "BuildCache", default, deserialize_with = "null_default_vec")]
    pub build_cache: Vec<BuildDisk>,
    #[serde(rename = "LayersSize", default)]
    pub layers_size: u64,
}
#[derive(Debug, Clone, Deserialize)]
pub struct ImageDisk {
    #[serde(rename = "Size", default)]
    pub size: u64,
    #[serde(rename = "SharedSize", default)]
    pub shared: u64,
    #[serde(rename = "RepoTags", default, deserialize_with = "null_default_vec")]
    pub tags: Vec<String>,
}
#[derive(Debug, Clone, Deserialize)]
pub struct BuildDisk {
    #[serde(rename = "Size", default)]
    pub size: u64,
    #[serde(rename = "InUse", default)]
    pub in_use: bool,
    #[serde(rename = "Shared", default)]
    pub is_shared: bool,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Info {
    #[serde(rename = "ServerVersion", default)]
    pub version: String,
}
#[derive(Debug, Clone, Deserialize)]
pub struct Stats {
    #[serde(rename = "cpu_stats")]
    cpu: CpuStats,
    #[serde(rename = "precpu_stats")]
    precpu: CpuStats,
    #[serde(rename = "memory_stats")]
    memory: MemoryStats,
}
#[derive(Debug, Clone, Deserialize, Default)]
struct CpuStats {
    #[serde(default)]
    cpu_usage: CpuUsage,
    #[serde(default)]
    system_cpu_usage: u64,
    #[serde(default)]
    online_cpus: u64,
}
#[derive(Debug, Clone, Deserialize, Default)]
struct CpuUsage {
    #[serde(default)]
    total_usage: u64,
}
#[derive(Debug, Clone, Deserialize, Default)]
struct MemoryStats {
    #[serde(default)]
    usage: u64,
    #[serde(default)]
    limit: u64,
    #[serde(default)]
    stats: std::collections::HashMap<String, u64>,
}
#[derive(Debug, Clone)]
pub struct StatView {
    pub cpu: f64,
    pub memory: u64,
    pub limit: u64,
}
impl Stats {
    pub fn view(&self) -> StatView {
        let c = self
            .cpu
            .cpu_usage
            .total_usage
            .saturating_sub(self.precpu.cpu_usage.total_usage) as f64;
        let s = self
            .cpu
            .system_cpu_usage
            .saturating_sub(self.precpu.system_cpu_usage) as f64;
        let n = if self.cpu.online_cpus > 0 {
            self.cpu.online_cpus
        } else {
            1
        };
        let cpu = if s > 0. { c / s * 100. * n as f64 } else { 0. };
        let cache = self
            .memory
            .stats
            .get("inactive_file")
            .or_else(|| self.memory.stats.get("cache"))
            .copied()
            .unwrap_or(0);
        StatView {
            cpu,
            memory: self.memory.usage.saturating_sub(cache),
            limit: self.memory.limit,
        }
    }
}
impl Engine {
    pub fn new(host: Option<String>) -> Result<Self, String> {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR").ok();
        let host = host.filter(|s| !s.is_empty()).unwrap_or_else(|| {
            runtime_dir
                .as_ref()
                .map(|p| format!("unix://{p}/docker.sock"))
                .unwrap_or_default()
        });
        if host.is_empty() {
            return Err("XDG_RUNTIME_DIR 或 DOCKER_HOST 必须设置".into());
        }
        if !host.starts_with("unix://") {
            return Err("DOCKER_HOST 仅支持 unix://；不会回退到其它 daemon".into());
        }
        let path = host.trim_start_matches("unix://");
        let client = Client::builder()
            .unix_socket(path)
            .build()
            .map_err(|_| "无法初始化 Docker socket 客户端")?;
        let can_stop_local_daemon = is_default_docker_socket(&host, runtime_dir.as_deref());
        Ok(Self {
            client,
            host,
            can_stop_local_daemon,
        })
    }
    async fn request(&self, method: Method, path: &str) -> Result<Response, String> {
        let url = format!("http://docker/v1.47{path}");
        self.client
            .request(method, url)
            .timeout(Duration::from_secs(10))
            .send()
            .await
            .map_err(|_| "Docker 启动中…".into())
    }
    async fn json<T: for<'de> Deserialize<'de>>(&self, path: &str) -> Result<T, String> {
        let r = self.request(Method::GET, path).await?;
        if !r.status().is_success() {
            return Err(docker_error(r).await);
        }
        r.json().await.map_err(|_| "Docker API 响应无法解析".into())
    }
    async fn action(&self, method: Method, path: &str) -> Result<(), String> {
        let r = self.request(method, path).await?;
        if r.status().is_success()
            || r.status() == StatusCode::NO_CONTENT
            || r.status() == StatusCode::NOT_MODIFIED
        {
            return Ok(());
        }
        Err(docker_error(r).await)
    }
    pub async fn ping(&self) -> Result<(), String> {
        let r = self.request(Method::GET, "/_ping").await?;
        if r.status().is_success() {
            Ok(())
        } else {
            Err("Docker 启动中…".into())
        }
    }
    pub async fn containers(&self) -> Result<Vec<Container>, String> {
        Ok(self
            .json::<Option<Vec<Container>>>("/containers/json?all=1")
            .await?
            .unwrap_or_default())
    }
    pub async fn images(&self) -> Result<Vec<Image>, String> {
        Ok(self
            .json::<Option<Vec<Image>>>("/images/json?all=1")
            .await?
            .unwrap_or_default())
    }
    pub async fn volumes(&self) -> Result<Vec<Volume>, String> {
        #[derive(Deserialize)]
        struct V {
            #[serde(default, rename = "Volumes", deserialize_with = "null_default_vec")]
            volumes: Vec<Volume>,
        }
        Ok(self.json::<V>("/volumes").await?.volumes)
    }
    pub async fn info(&self) -> Result<Info, String> {
        self.json("/info").await
    }
    pub async fn disk(&self) -> Result<Disk, String> {
        self.json("/system/df").await
    }
    pub async fn stats(&self, id: &str) -> Result<StatView, String> {
        let s: Stats = self
            .json(&format!("/containers/{}/stats?stream=false", enc(id)))
            .await?;
        Ok(s.view())
    }
    pub async fn logs(&self, id: &str) -> Result<(Response, bool), String> {
        #[derive(Deserialize)]
        struct Inspect {
            #[serde(rename = "Config")]
            config: Option<InspectConfig>,
        }
        #[derive(Deserialize)]
        struct InspectConfig {
            #[serde(rename = "Tty", default)]
            tty: bool,
        }
        let inspect: Inspect = self.json(&format!("/containers/{}/json", enc(id))).await?;
        let tty = inspect.config.is_some_and(|config| config.tty);
        let response=self.client.get(format!("http://docker/v1.47/containers/{}/logs?follow=1&stdout=1&stderr=1&timestamps=1&tail=500",enc(id))).send().await.map_err(|_| "Docker 启动中…")?;
        Ok((response, tty))
    }
    pub async fn start(&self, id: &str) -> Result<(), String> {
        self.action(Method::POST, &format!("/containers/{}/start", enc(id)))
            .await
    }
    pub async fn stop(&self, id: &str) -> Result<(), String> {
        self.action(Method::POST, &format!("/containers/{}/stop?t=10", enc(id)))
            .await
    }
    pub async fn restart(&self, id: &str) -> Result<(), String> {
        self.action(
            Method::POST,
            &format!("/containers/{}/restart?t=10", enc(id)),
        )
        .await
    }
    pub async fn remove_container(&self, id: &str) -> Result<(), String> {
        self.action(
            Method::DELETE,
            &format!("/containers/{}?force=1&v=false", enc(id)),
        )
        .await
    }
    pub async fn remove_image(&self, id: &str) -> Result<(), String> {
        self.action(Method::DELETE, &format!("/images/{}?force=false", enc(id)))
            .await
    }
    pub async fn remove_volume(&self, name: &str) -> Result<(), String> {
        self.action(Method::DELETE, &format!("/volumes/{}", enc(name)))
            .await
    }
    pub async fn prune_images(&self) -> Result<Value, String> {
        self.json_post("/images/prune?filters=%7B%22dangling%22%3A%5B%22true%22%5D%7D")
            .await
    }
    pub async fn prune_build(&self) -> Result<Value, String> {
        self.json_post("/build/prune").await
    }
    async fn json_post(&self, path: &str) -> Result<Value, String> {
        let r = self.request(Method::POST, path).await?;
        if !r.status().is_success() {
            return Err(docker_error(r).await);
        }
        r.json().await.map_err(|_| "Docker API 响应无法解析".into())
    }
    pub async fn exec_has_bash(&self, id: &str) -> bool {
        #[derive(Deserialize)]
        struct E {
            #[serde(rename = "Id")]
            id: String,
        }
        let body = serde_json::json!({"AttachStdout":false,"AttachStderr":false,"Cmd":["/bin/bash","-lc","exit 0"]});
        let Ok(r) = self
            .client
            .post(format!("http://docker/v1.47/containers/{}/exec", enc(id)))
            .json(&body)
            .send()
            .await
        else {
            return false;
        };
        let Ok(e) = r.json::<E>().await else {
            return false;
        };
        let start = self
            .client
            .post(format!("http://docker/v1.47/exec/{}/start", enc(&e.id)))
            .json(&serde_json::json!({"Detach":true,"Tty":false}))
            .send()
            .await;
        start.is_ok_and(|r| r.status().is_success())
    }
}
fn enc(s: &str) -> String {
    url_encode(s)
}
fn url_encode(s: &str) -> String {
    s.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-_.".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}
async fn docker_error(r: Response) -> String {
    let status = r.status();
    let body = r.text().await.unwrap_or_default();
    let message = serde_json::from_str::<Value>(&body)
        .ok()
        .and_then(|v| v.get("message").and_then(Value::as_str).map(str::to_owned));
    format!(
        "Docker API {status}: {}",
        message.unwrap_or_else(|| "请求失败".into())
    )
}
/// Docker multiplexed stream frames: [stream, 0,0,0, big-endian length, payload].
pub fn drain_raw_log_lines(buffer: &mut Vec<u8>) -> Vec<String> {
    let mut out = Vec::new();
    while let Some(end) = buffer.iter().position(|b| *b == b'\n') {
        let line = buffer.drain(..=end).collect::<Vec<_>>();
        out.push(
            String::from_utf8_lossy(&line[..line.len().saturating_sub(1)])
                .trim_end_matches('\r')
                .to_owned(),
        );
    }
    out
}
pub fn drain_log_frames(buffer: &mut Vec<u8>) -> Vec<String> {
    let mut out = Vec::new();
    let mut consumed = 0;
    while buffer.len().saturating_sub(consumed) >= 8 {
        let frame = &buffer[consumed..];
        if frame[1..4] != [0, 0, 0] {
            break;
        }
        let n = u32::from_be_bytes([frame[4], frame[5], frame[6], frame[7]]) as usize;
        if frame.len() < 8 + n {
            break;
        }
        if let Ok(line) = std::str::from_utf8(&frame[8..8 + n]) {
            out.push(line.trim_end_matches(['\r', '\n']).to_string());
        }
        consumed += 8 + n;
    }
    buffer.drain(..consumed);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compose_and_stats_decode() {
        let c:Container=serde_json::from_str(r#"{"Id":"abc","Names":["/web"],"Image":"nginx","State":"running","Status":"Up 2 minutes","Labels":{"com.docker.compose.project":"demo"},"Ports":[{"IP":"0.0.0.0","PrivatePort":80,"PublicPort":8080,"Type":"tcp"}]}"#).unwrap();
        assert_eq!(c.labels["com.docker.compose.project"], "demo");
        assert_eq!(c.ports[0].public, Some(8080));
        let s:Stats=serde_json::from_str(r#"{"cpu_stats":{"cpu_usage":{"total_usage":30},"system_cpu_usage":200,"online_cpus":2},"precpu_stats":{"cpu_usage":{"total_usage":10},"system_cpu_usage":100,"online_cpus":2},"memory_stats":{"usage":1000,"limit":5000,"stats":{"inactive_file":200}}}"#).unwrap();
        assert!((s.view().cpu - 40.).abs() < 0.01);
        assert_eq!(s.view().memory, 800)
    }
    #[test]
    fn null_and_empty_collections_are_accepted_and_df_supplies_volume_usage() {
        let disk:Disk=serde_json::from_str(r#"{"Images":null,"Containers":null,"Volumes":[{"Name":"data","UsageData":{"Size":1234,"RefCount":2}}],"BuildCache":null}"#).unwrap();
        assert!(
            disk.images.is_empty() && disk.containers.is_empty() && disk.build_cache.is_empty()
        );
        #[derive(Deserialize)]
        struct V {
            #[serde(rename = "Volumes", default, deserialize_with = "null_default_vec")]
            volumes: Vec<Volume>,
        }
        let mut volumes = serde_json::from_str::<V>(
            r#"{"Volumes":[{"Name":"data","UsageData":null},{"Name":"unknown"}]}"#,
        )
        .unwrap()
        .volumes;
        merge_volume_usage(&mut volumes, &disk);
        assert_eq!(volumes[0].usage.as_ref().unwrap().size, 1234);
        assert!(volumes[1].usage.is_none());
        let image: Image = serde_json::from_str(r#"{"Id":"i","RepoTags":null,"Size":1}"#).unwrap();
        assert!(image.tags.is_empty());
    }
    #[test]
    fn build_cache_estimate_skips_in_use_and_shared_entries() {
        let entries = vec![
            BuildDisk {
                size: 100,
                in_use: false,
                is_shared: false,
            },
            BuildDisk {
                size: 200,
                in_use: true,
                is_shared: false,
            },
            BuildDisk {
                size: 300,
                in_use: false,
                is_shared: true,
            },
        ];
        assert_eq!(reclaimable_build_cache(&entries), 100);
    }
    #[test]
    fn multiplex_logs() {
        let mut b = vec![1, 0, 0, 0, 0, 0, 0, 4];
        b.extend(b"hey\n");
        b.extend([2, 0, 0, 0, 0, 0, 0, 3]);
        b.extend(b"err");
        let mut partial = b[..11].to_vec();
        assert!(drain_log_frames(&mut partial).is_empty());
        partial.extend_from_slice(&b[11..]);
        assert_eq!(drain_log_frames(&mut partial), ["hey", "err"]);
        assert!(partial.is_empty());
        let mut raw = b"line one\r\npart".to_vec();
        assert_eq!(drain_raw_log_lines(&mut raw), ["line one"]);
        raw.extend_from_slice(b"ial\n");
        assert_eq!(drain_raw_log_lines(&mut raw), ["partial"]);
        assert!(raw.is_empty());
    }
    #[test]
    fn url_encoded_ids_and_hazard_gates() {
        assert_eq!(enc("vol/a"), "vol%2Fa");
        assert!(!volume_delete_confirmed(0));
        assert!(!volume_delete_confirmed(1));
        assert!(volume_delete_confirmed(2));
        assert!(is_default_docker_socket(
            "unix:///run/user/1000/docker.sock",
            Some("/run/user/1000")
        ));
        assert!(!is_default_docker_socket(
            "unix:///tmp/docker-test.sock",
            Some("/run/user/1000")
        ));
    }
}
