use anyhow::{bail, Context, Result};
use futures_util::StreamExt;
use reqwest::{header, Client, Method, Response};
use serde_json::Value;
use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use url::Url;

pub const UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const API: &str = "https://api.bilibili.com";
const PASSPORT: &str = "https://passport.bilibili.com";
const SEARCH: &str = "https://s.search.bilibili.com";
const MAX_RESPONSE_BYTES: usize = 8 * 1024 * 1024;
const MIXIN_TAB: [usize; 64] = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29,
    28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25,
    54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
];
static COOLDOWN_UNTIL: AtomicU64 = AtomicU64::new(0);

#[derive(Clone)]
pub struct Api {
    client: Client,
    cookie: String,
    wbi: Arc<Mutex<Option<(String, String)>>>,
}

impl Api {
    pub fn new(cookie: String) -> Result<Self> {
        let cookie = clean_cookie(&cookie);
        let client = Client::builder()
            .user_agent(UA)
            .timeout(Duration::from_secs(20))
            // Do not forward an explicit Cookie header through a redirect.
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .context("无法初始化 B 站网络客户端")?;
        Ok(Self {
            client,
            cookie,
            wbi: Arc::new(Mutex::new(None)),
        })
    }

    pub fn logged_in(&self) -> bool {
        has_cookie(&self.cookie, "SESSDATA")
    }

    /// The caller may write this value only to bilitui's private runtime cookie file.
    pub fn cookie(&self) -> &str {
        &self.cookie
    }

    /// Fetches an anonymous buvid only when the caller explicitly initializes the API.
    pub async fn initialize(&mut self) -> Result<()> {
        if self.cookie.contains("buvid3=") && self.cookie.contains("buvid4=") {
            return Ok(());
        }
        let value = self
            .request(Method::GET, API, "/x/frontend/finger/spi", &[], None, false)
            .await?;
        let data = value
            .get("data")
            .and_then(Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("B 站未返回设备标识"))?;
        for name in ["b_3", "b_4"] {
            if let Some(value) = data.get(name).and_then(Value::as_str) {
                if !value.is_empty() && value.len() < 256 && value.bytes().all(is_cookie_value) {
                    let cookie_name = if name == "b_3" { "buvid3" } else { "buvid4" };
                    set_cookie(&mut self.cookie, cookie_name, value);
                }
            }
        }
        Ok(())
    }

    /// Performs a public/read endpoint request. The path is always relative to the fixed API host.
    pub async fn get(&self, path: &str, params: &[(&str, String)]) -> Result<Value> {
        let value = self
            .request(Method::GET, API, path, params, None, true)
            .await?;
        unwrap_api(value)
    }

    /// Fetches anonymous search suggestions, keeping the request on Bilibili's search host.
    pub async fn suggest(&self, query: &str) -> Result<Vec<String>> {
        if query.trim().is_empty() || query.len() > 128 {
            return Ok(Vec::new());
        }
        let value = self
            .request(
                Method::GET,
                SEARCH,
                "/main/suggest",
                &[
                    ("term", query.to_owned()),
                    ("main_ver", "v1".to_owned()),
                    ("highlight", "".to_owned()),
                ],
                None,
                false,
            )
            .await?;
        let values = value
            .pointer("/result/tag")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|item| item.get("value").and_then(Value::as_str))
            .filter(|item| !item.trim().is_empty())
            .take(20)
            .map(str::to_owned)
            .collect();
        Ok(values)
    }

    /// Signs a WBI endpoint using the current keys returned by `/x/web-interface/nav`.
    pub async fn signed(&self, path: &str, params: &[(&str, String)]) -> Result<Value> {
        if !path.starts_with("/") || !path.contains("/wbi/") {
            bail!("WBI 请求路径无效");
        }
        let cached = {
            self.wbi
                .lock()
                .map_err(|_| anyhow::anyhow!("WBI 缓存不可用"))?
                .clone()
        };
        let (img, sub) = if let Some(keys) = cached {
            keys
        } else {
            // `/nav` still includes `wbi_img` when an anonymous request reports -101.
            let nav = self
                .request(Method::GET, API, "/x/web-interface/nav", &[], None, true)
                .await?;
            let code = nav.get("code").and_then(Value::as_i64).unwrap_or(0);
            if code != 0 && code != -101 {
                let _ = unwrap_api(nav)?;
                unreachable!("non-zero API code must fail");
            }
            if nav
                .pointer("/data/wbi_img")
                .and_then(Value::as_object)
                .is_none()
            {
                bail!("B 站未提供 WBI 密钥");
            }
            let img = nav
                .pointer("/data/wbi_img/img_url")
                .and_then(Value::as_str)
                .and_then(key_from_url)
                .ok_or_else(|| anyhow::anyhow!("B 站未提供 WBI 图片密钥"))?;
            let sub = nav
                .pointer("/data/wbi_img/sub_url")
                .and_then(Value::as_str)
                .and_then(key_from_url)
                .ok_or_else(|| anyhow::anyhow!("B 站未提供 WBI 子密钥"))?;
            let mut cache = self
                .wbi
                .lock()
                .map_err(|_| anyhow::anyhow!("WBI 缓存不可用"))?;
            *cache = Some((img.clone(), sub.clone()));
            (img, sub)
        };
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let signed = sign(params, &img, &sub, now)?;
        self.request(
            Method::GET,
            API,
            path,
            &signed
                .iter()
                .map(|(k, v)| (k.as_str(), v.clone()))
                .collect::<Vec<_>>(),
            None,
            true,
        )
        .await
        .and_then(unwrap_api)
    }

    /// Posts only to the application's explicit set of user-action endpoints.
    pub async fn post(&self, path: &str, params: &[(&str, String)]) -> Result<Value> {
        if !self.logged_in() {
            bail!("此操作需要先登录 B 站");
        }
        if !write_path_allowed(path) {
            bail!("该写入接口不在允许列表中");
        }
        let csrf = cookie_value(&self.cookie, "bili_jct")
            .filter(|v| !v.is_empty())
            .ok_or_else(|| anyhow::anyhow!("登录状态缺少 CSRF 校验值"))?;
        let mut fields: Vec<(String, String)> = params
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect();
        if !fields.iter().any(|(k, _)| k == "csrf") {
            fields.push(("csrf".into(), csrf.to_owned()));
        }
        let value = self
            .request(
                Method::POST,
                API,
                path,
                &fields
                    .iter()
                    .map(|(k, v)| (k.as_str(), v.clone()))
                    .collect::<Vec<_>>(),
                Some(csrf),
                true,
            )
            .await?;
        let code = value.get("code").and_then(Value::as_i64).unwrap_or(0);
        if code != 0 {
            return unwrap_api(value);
        }
        Ok(value
            .get("data")
            .or_else(|| value.get("result"))
            .cloned()
            .unwrap_or(Value::Null))
    }

    /// Returns QR content and its opaque polling key; it never starts polling itself.
    pub async fn qr_generate(&self) -> Result<(String, String)> {
        let value = self
            .request(
                Method::GET,
                PASSPORT,
                "/x/passport-login/web/qrcode/generate",
                &[],
                None,
                false,
            )
            .await?;
        parse_qr_generate(value)
    }

    /// Polls once. A successful response must issue a complete new session.
    pub async fn qr_poll(&self, key: &str) -> Result<(i64, Option<String>)> {
        if !valid_qr_key(key) {
            bail!("二维码密钥格式无效");
        }
        let value = self
            .request(
                Method::GET,
                PASSPORT,
                "/x/passport-login/web/qrcode/poll",
                &[("qrcode_key", key.to_owned())],
                None,
                false,
            )
            .await?;
        parse_qr_poll(&self.cookie, value)
    }

    async fn request(
        &self,
        method: Method,
        host: &str,
        path: &str,
        params: &[(&str, String)],
        csrf: Option<&str>,
        use_cookie: bool,
    ) -> Result<Value> {
        validate_target(host, path)?;
        let now = epoch();
        let until = COOLDOWN_UNTIL.load(Ordering::Acquire);
        if until > now {
            bail!("B 站风控冷却中，还需等待 {} 秒", until - now);
        }
        let url = format!("{host}{path}");
        let mut builder = self.client.request(method.clone(), &url);
        builder = builder.header(header::REFERER, "https://www.bilibili.com/");
        if use_cookie && !self.cookie.is_empty() {
            builder = builder.header(header::COOKIE, self.cookie.as_str());
        }
        if let Some(csrf) = csrf {
            builder = builder.header("x-csrf-token", csrf);
        }
        if method == Method::GET {
            builder = builder.query(params);
        } else {
            builder = builder.form(params);
        }
        let response = builder
            .send()
            .await
            .map_err(|error| anyhow::anyhow!("B 站网络请求失败：{}", error.without_url()))?;
        let set_cookies = response
            .headers()
            .get_all(header::SET_COOKIE)
            .iter()
            .filter_map(|v| v.to_str().ok())
            .map(str::to_owned)
            .collect::<Vec<_>>();
        let mut value = self.read_response(response).await?;
        if !set_cookies.is_empty() {
            value["_set_cookie"] = serde_json::json!(set_cookies);
        }
        Ok(value)
    }

    async fn read_response(&self, response: Response) -> Result<Value> {
        let status = response.status();
        if status.as_u16() == 412 || status.as_u16() == 429 {
            set_cooldown(60);
            bail!(
                "B 站触发风控（HTTP {}），已暂停后续请求 60 秒；请稍后重试",
                status.as_u16()
            );
        }
        if !status.is_success() {
            bail!("B 站请求失败（HTTP {}）", status.as_u16());
        }
        if response
            .content_length()
            .is_some_and(|n| n > MAX_RESPONSE_BYTES as u64)
        {
            bail!("B 站响应超过 8 MiB 上限");
        }
        let mut stream = response.bytes_stream();
        let mut bytes = Vec::new();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|_| anyhow::anyhow!("读取 B 站响应失败"))?;
            if bytes.len().saturating_add(chunk.len()) > MAX_RESPONSE_BYTES {
                bail!("B 站响应超过 8 MiB 上限");
            }
            bytes.extend_from_slice(&chunk);
        }
        let value: Value =
            serde_json::from_slice(&bytes).map_err(|_| anyhow::anyhow!("B 站返回了无效数据"))?;
        if value.get("code").and_then(Value::as_i64) == Some(-352)
            || value.get("code").and_then(Value::as_i64) == Some(-412)
        {
            set_cooldown(60);
            bail!(
                "B 站触发风控（-{}），已暂停后续请求 60 秒；请降低请求频率",
                value["code"].as_i64().unwrap_or_default().abs()
            );
        }
        Ok(value)
    }
}

pub fn sign(
    params: &[(&str, String)],
    img: &str,
    sub: &str,
    timestamp: u64,
) -> Result<Vec<(String, String)>> {
    if img.len() != 32
        || sub.len() != 32
        || !img
            .bytes()
            .chain(sub.bytes())
            .all(|b| b.is_ascii_alphanumeric())
    {
        bail!("WBI 密钥格式无效");
    }
    let raw = format!("{img}{sub}");
    let mixin = MIXIN_TAB
        .iter()
        .take(32)
        .map(|&i| raw.as_bytes()[i] as char)
        .collect::<String>();
    let mut values = BTreeMap::<String, String>::new();
    for (key, value) in params {
        if *key == "w_rid" || *key == "wts" || key.is_empty() || key.contains(['&', '=']) {
            continue;
        }
        let cleaned = value
            .chars()
            .filter(|c| !matches!(c, '!' | '\'' | '(' | ')' | '*'))
            .collect::<String>();
        values.insert((*key).to_owned(), cleaned);
    }
    values.insert("wts".into(), timestamp.to_string());
    let query = values
        .iter()
        .map(|(k, v)| format!("{}={}", form_encode(k), form_encode(v)))
        .collect::<Vec<_>>()
        .join("&");
    let digest = format!("{:x}", md5::compute(format!("{query}{mixin}")));
    let mut signed = values.into_iter().collect::<Vec<_>>();
    signed.push(("w_rid".into(), digest));
    Ok(signed)
}

fn unwrap_api(value: Value) -> Result<Value> {
    let code = value.get("code").and_then(Value::as_i64).unwrap_or(0);
    if code == -352 || code == -412 {
        set_cooldown(60);
        bail!("B 站触发风控（{code}），已暂停后续请求 60 秒；请降低请求频率");
    }
    if code != 0 {
        let message = match code {
            -101 => "登录状态失效，请重新扫码登录",
            -400 => "请求参数不正确",
            -403 => "B 站拒绝了此请求",
            -404 => "B 站内容不存在或不可见",
            _ => "B 站接口返回错误",
        };
        let reason = value
            .get("message")
            .or_else(|| value.get("msg"))
            .and_then(Value::as_str)
            .map(safe_api_message)
            .filter(|s| !s.is_empty());
        if let Some(reason) = reason {
            bail!("{message}（错误码 {code}）：{reason}");
        }
        bail!("{message}（错误码 {code}）");
    }
    value
        .get("data")
        .or_else(|| value.get("result"))
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("B 站响应缺少数据"))
}

fn safe_api_message(text: &str) -> String {
    if ["sessdata", "bili_jct", "qrcode_key", "cookie"]
        .iter()
        .any(|field| text.to_ascii_lowercase().contains(field))
    {
        return "接口返回了凭据相关错误，敏感内容已隐藏".into();
    }
    text.split_whitespace()
        .map(|word| {
            if word.contains("://") {
                "[链接已隐藏]"
            } else {
                word
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .filter(|c| !c.is_control())
        .take(160)
        .collect()
}

fn qr_url(value: &str) -> Option<Url> {
    let url = Url::parse(value).ok()?;
    let host = url.host_str()?;
    (url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && (host == "bilibili.com" || host.ends_with(".bilibili.com")))
    .then_some(url)
}

fn parse_qr_generate(value: Value) -> Result<(String, String)> {
    let data = unwrap_api(value)?;
    let url = data
        .get("url")
        .and_then(Value::as_str)
        .and_then(qr_url)
        .ok_or_else(|| {
            anyhow::anyhow!("B 站返回的二维码链接无效：需要 HTTPS 的 bilibili.com 域名")
        })?;
    let key = data
        .get("qrcode_key")
        .and_then(Value::as_str)
        .filter(|s| valid_qr_key(s))
        .ok_or_else(|| anyhow::anyhow!("B 站未返回有效二维码密钥"))?;
    Ok((url.to_string(), key.to_owned()))
}

fn cookie_query_value(value: &str) -> String {
    value
        .as_bytes()
        .iter()
        .map(|byte| {
            if is_cookie_value(*byte) {
                (*byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect()
}

fn parse_qr_poll(previous: &str, value: Value) -> Result<(i64, Option<String>)> {
    let data = unwrap_api(value.clone())?;
    let state = data
        .get("code")
        .and_then(Value::as_i64)
        .ok_or_else(|| anyhow::anyhow!("B 站登录状态缺少 data.code"))?;
    if state != 0 {
        return Ok((state, None));
    }
    let mut issued = String::new();
    for header in value
        .get("_set_cookie")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
    {
        absorb_set_cookie(&mut issued, header);
    }
    if let Some(url) = data
        .get("url")
        .and_then(Value::as_str)
        .and_then(|s| Url::parse(s).ok())
    {
        if url.scheme() == "https"
            && matches!(
                url.host_str(),
                Some("passport.bilibili.com" | "passport.biligame.com")
            )
        {
            for (key, value) in url.query_pairs() {
                if ["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5"]
                    .contains(&key.as_ref())
                {
                    set_cookie(&mut issued, &key, &cookie_query_value(&value));
                }
            }
        }
    }
    if !has_cookie(&issued, "SESSDATA") || !has_cookie(&issued, "bili_jct") {
        bail!("登录成功响应未包含完整的新会话 cookie");
    }
    let mut cookies = clean_cookie(previous);
    for pair in issued.split("; ") {
        if let Some((key, value)) = pair.split_once('=') {
            set_cookie(&mut cookies, key, value);
        }
    }
    if cookies.len() > 16384 {
        bail!("B 站登录 cookie 超过 16 KiB 上限");
    }
    Ok((state, Some(cookies)))
}

fn validate_target(host: &str, path: &str) -> Result<()> {
    if !path.starts_with('/')
        || path.contains(['?', '#', '\\'])
        || path.split('/').any(|p| p == "." || p == "..")
    {
        bail!("B 站请求路径无效");
    }
    let allowed = match host {
        API => path.starts_with("/x/") || path.starts_with("/b/") || path.starts_with("/bapis/"),
        SEARCH => path == "/main/suggest",
        PASSPORT => matches!(
            path,
            "/x/passport-login/web/qrcode/generate" | "/x/passport-login/web/qrcode/poll"
        ),
        _ => false,
    };
    if !allowed {
        bail!("B 站请求目标不在允许范围内");
    }
    Ok(())
}

fn write_path_allowed(path: &str) -> bool {
    matches!(
        path,
        "/x/web-interface/archive/like"
            | "/x/web-interface/coin/add"
            | "/x/v3/fav/resource/deal"
            | "/x/v2/history/toview/add"
            | "/x/v2/history/toview/del"
            | "/x/click-interface/web/heartbeat"
    )
}

fn key_from_url(value: &str) -> Option<String> {
    let filename = value.rsplit('/').next()?.split('.').next()?;
    (filename.len() == 32 && filename.bytes().all(|b| b.is_ascii_alphanumeric()))
        .then(|| filename.to_owned())
}

fn form_encode(value: &str) -> String {
    let mut out = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            b' ' => out.push_str("%20"),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn clean_cookie(cookie: &str) -> String {
    cookie
        .split(';')
        .filter_map(|part| {
            let (name, value) = part.trim().split_once('=')?;
            let name = name.trim();
            let value = value.trim();
            if valid_cookie_name(name) && value.bytes().all(is_cookie_value) {
                Some(format!("{name}={value}"))
            } else {
                None
            }
        })
        .collect::<Vec<_>>()
        .join("; ")
}
fn valid_cookie_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}
fn is_cookie_value(b: u8) -> bool {
    (0x21..=0x7e).contains(&b) && !matches!(b, b';' | b',')
}
fn cookie_value<'a>(cookie: &'a str, name: &str) -> Option<&'a str> {
    cookie.split("; ").find_map(|part| {
        let (key, value) = part.split_once('=')?;
        (key == name).then_some(value)
    })
}
fn has_cookie(cookie: &str, name: &str) -> bool {
    cookie_value(cookie, name).is_some_and(|value| !value.is_empty())
}
fn set_cookie(cookie: &mut String, name: &str, value: &str) {
    if !valid_cookie_name(name) || !value.bytes().all(is_cookie_value) {
        return;
    }
    if !valid_cookie_name(name) || !value.bytes().all(is_cookie_value) {
        return;
    }
    let mut pairs = cookie
        .split("; ")
        .filter_map(|part| part.split_once('='))
        .filter(|(key, _)| *key != name)
        .map(|(key, value)| format!("{key}={value}"))
        .collect::<Vec<_>>();
    pairs.push(format!("{name}={value}"));
    *cookie = pairs.join("; ");
}
fn absorb_set_cookie(cookie: &mut String, value: &str) {
    let pair = value.split(';').next().unwrap_or("");
    if let Some((name, value)) = pair.trim().split_once('=') {
        set_cookie(cookie, name.trim(), value.trim());
    }
}
fn valid_qr_key(key: &str) -> bool {
    key.len() == 32 && key.bytes().all(|b| b.is_ascii_hexdigit())
}
fn epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn set_cooldown(seconds: u64) {
    COOLDOWN_UNTIL.fetch_max(epoch().saturating_add(seconds), Ordering::AcqRel);
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct WbiFixture {
        img_key: String,
        sub_key: String,
        timestamp: u64,
        params: Vec<(String, String)>,
        expected_query: String,
        expected_w_rid: String,
    }

    #[test]
    fn wbi_signature_matches_fixed_fixture() {
        let fixture: WbiFixture =
            serde_json::from_str(include_str!("../fixtures/wbi.json")).unwrap();
        let params = fixture
            .params
            .iter()
            .map(|(k, v)| (k.as_str(), v.clone()))
            .collect::<Vec<_>>();
        let signed = sign(
            &params,
            &fixture.img_key,
            &fixture.sub_key,
            fixture.timestamp,
        )
        .unwrap();
        let actual_query = signed
            .iter()
            .filter(|(key, _)| key != "w_rid")
            .map(|(k, v)| format!("{}={}", form_encode(k), form_encode(v)))
            .collect::<Vec<_>>()
            .join("&");
        assert_eq!(actual_query, fixture.expected_query);
        assert_eq!(form_encode("hello world"), "hello%20world");
        assert_eq!(
            signed.last().unwrap(),
            &("w_rid".to_owned(), fixture.expected_w_rid)
        );
    }

    #[test]
    fn qr_urls_accept_current_account_host_and_reject_lookalikes() {
        let key = "0123456789abcdef0123456789abcdef";
        for url in [
            "https://account.bilibili.com/h5/account-h5/auth/scan-web?fixture=1",
            "https://passport.bilibili.com/qrcode",
            "https://bilibili.com/login",
        ] {
            assert!(parse_qr_generate(
                serde_json::json!({"code":0,"data":{"url":url,"qrcode_key":key}})
            )
            .is_ok());
        }
        for url in [
            "http://account.bilibili.com/",
            "https://bilibili.com.evil/",
            "https://evilbilibili.com/",
            "https://bilibili.com@evil.example/",
            "https://user@account.bilibili.com/",
        ] {
            assert!(parse_qr_generate(
                serde_json::json!({"code":0,"data":{"url":url,"qrcode_key":key}})
            )
            .is_err());
        }
        let error =
            parse_qr_generate(serde_json::json!({"code":-400,"message":"二维码暂时不可用"}))
                .unwrap_err()
                .to_string();
        assert!(error.contains("-400") && error.contains("二维码暂时不可用"));
    }
    #[test]
    fn qr_poll_checks_outer_errors_and_requires_new_session_cookies() {
        assert!(
            parse_qr_poll("", serde_json::json!({"code":-400,"message":"无效请求"}))
                .unwrap_err()
                .to_string()
                .contains("无效请求")
        );
        assert_eq!(
            parse_qr_poll("", serde_json::json!({"code":0,"data":{"code":86101}})).unwrap(),
            (86101, None)
        );
        assert!(parse_qr_poll(
            "SESSDATA=old; bili_jct=old",
            serde_json::json!({"code":0,"data":{"code":0}})
        )
        .is_err());
        let (_,cookie)=parse_qr_poll("buvid3=device",serde_json::json!({"code":0,"data":{"code":0},"_set_cookie":["SESSDATA=fixture-session; Path=/; Secure","bili_jct=fixture-csrf"]})).unwrap();
        let cookie = cookie.unwrap();
        assert!(
            cookie.contains("buvid3=device")
                && cookie.contains("SESSDATA=fixture-session")
                && cookie.contains("bili_jct=fixture-csrf")
        );
        assert!(parse_qr_poll("",serde_json::json!({"code":0,"data":{"code":0,"url":"http://passport.bilibili.com/?SESSDATA=fake&bili_jct=fake"}})).is_err());
        let (_,cookie)=parse_qr_poll("",serde_json::json!({"code":0,"data":{"code":0,"url":"https://passport.biligame.com/crossDomain?SESSDATA=fixture%2Csession&bili_jct=fixture-csrf"}})).unwrap();
        assert!(Api::new(cookie.clone().unwrap()).unwrap().logged_in());
        assert!(cookie.unwrap().contains("SESSDATA=fixture%2Csession"));
        assert!(safe_api_message("qrcode_key=secret-value").contains("已隐藏"));
        assert!(
            !safe_api_message("https://example.invalid/?qrcode_key=secret-value")
                .contains("secret-value")
        );
    }

    #[test]
    fn api_parser_and_cookie_boundaries_use_fixed_fixture() {
        let fixture: Value = serde_json::from_str(include_str!("../fixtures/video.json")).unwrap();
        assert_eq!(unwrap_api(fixture).unwrap()["bvid"], "BV1xx411c7mD");
        assert!(Api::new("SESSDATA=abc; bili_jct=csrf".into())
            .unwrap()
            .logged_in());
        assert!(!Api::new("bili_jct=csrf".into()).unwrap().logged_in());
        assert!(validate_target(API, "/x/web-interface/view").is_ok());
        assert!(validate_target("https://evil.example", "/x/web-interface/view").is_err());
        assert!(validate_target(API, "/x/../secret").is_err());
        assert!(validate_target(API, "/x/view?cookie=secret").is_err());
        assert!(!write_path_allowed("/x/web-interface/view"));
    }
}
