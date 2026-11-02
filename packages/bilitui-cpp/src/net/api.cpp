#include "net/api.hpp"

#include <curl/curl.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <memory>
#include <stdexcept>

#include "core/text.hpp"

namespace bili {
namespace {
const std::string kApi = "https://api.bilibili.com";
const std::string kPassport = "https://passport.bilibili.com";
const std::string kSearch = "https://s.search.bilibili.com";
std::atomic<uint64_t> cooldown_until{0};
uint64_t epoch() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
}
void set_cooldown(uint64_t seconds) {
    const uint64_t target = epoch() + seconds;
    uint64_t current = cooldown_until.load();
    while (current < target && !cooldown_until.compare_exchange_weak(current, target)) {
    }
}
bool cookie_name_valid(const std::string& name) {
    return !name.empty() && std::all_of(name.begin(), name.end(), [](unsigned char c) { return std::isalnum(c) || c == '_' || c == '-'; });
}
bool cookie_byte(unsigned char c) { return c >= 0x21 && c <= 0x7E && c != ';' && c != ','; }
bool cookie_value_valid(const std::string& value) {
    return std::all_of(value.begin(), value.end(), [](unsigned char c) { return cookie_byte(c); });
}
std::vector<std::string> split(const std::string& text, const std::string& by) {
    std::vector<std::string> out;
    size_t at = 0;
    while (true) {
        const auto next = text.find(by, at);
        out.push_back(text.substr(at, next == std::string::npos ? next : next - at));
        if (next == std::string::npos) return out;
        at = next + by.size();
    }
}
void validate_target(const std::string& host, const std::string& path) {
    bool safe = !path.empty() && path[0] == '/' && path.find_first_of("?#\\") == std::string::npos;
    for (const auto& piece : split(path, "/")) safe = safe && piece != "." && piece != "..";
    if (!safe) throw std::runtime_error("B 站请求路径无效");
    bool allowed = false;
    if (host == kApi) allowed = path.rfind("/x/", 0) == 0;
    if (host == kSearch) allowed = path == "/main/suggest";
    if (host == kPassport) allowed = path == "/x/passport-login/web/qrcode/generate" || path == "/x/passport-login/web/qrcode/poll";
    if (!allowed) throw std::runtime_error("B 站请求目标不在允许范围内");
}
std::string encode_params(const Params& params) {
    std::string out;
    for (const auto& [name, value] : params) {
        if (!out.empty()) out += '&';
        out += form_encode(name) + "=" + form_encode(value);
    }
    return out;
}
std::optional<std::string> key_from_url(const std::string& url) {
    const auto slash = url.rfind('/');
    std::string name = slash == std::string::npos ? url : url.substr(slash + 1);
    name = name.substr(0, name.find('.'));
    const bool ok = name.size() == 32 && std::all_of(name.begin(), name.end(), [](unsigned char c) { return std::isalnum(c); });
    return ok ? std::optional(name) : std::nullopt;
}
bool valid_qr_key(const std::string& key) {
    return key.size() == 32 && std::all_of(key.begin(), key.end(), [](unsigned char c) { return std::isxdigit(c); });
}
struct UrlDeleter {
    void operator()(CURLU* url) const { curl_url_cleanup(url); }
};
using UrlPtr = std::unique_ptr<CURLU, UrlDeleter>;
std::string url_part(CURLU* url, CURLUPart part, unsigned flags = 0) {
    char* value = nullptr;
    std::string out;
    if (curl_url_get(url, part, &value, flags) == CURLUE_OK && value) out = value;
    curl_free(value);
    return out;
}
std::string percent_decode(const std::string& text) {
    int length = 0;
    char* raw = curl_easy_unescape(nullptr, text.c_str(), static_cast<int>(text.size()), &length);
    std::string out = raw ? std::string(raw, static_cast<size_t>(length)) : std::string{};
    curl_free(raw);
    return out;
}
std::string cookie_query_value(const std::string& value) {
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string out;
    for (const char raw : value) {
        const auto c = static_cast<unsigned char>(raw);
        if (cookie_byte(c)) {
            out += raw;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}
}  // namespace
std::string clean_cookie(const std::string& cookie) {
    std::string out;
    for (const auto& piece : split(cookie, ";")) {
        const auto eq = piece.find('=');
        if (eq == std::string::npos) continue;
        const std::string name = trim(piece.substr(0, eq));
        const std::string value = trim(piece.substr(eq + 1));
        if (cookie_name_valid(name) && cookie_value_valid(value)) {
            if (!out.empty()) out += "; ";
            out += name + "=" + value;
        }
    }
    return out;
}
std::optional<std::string> cookie_value(const std::string& cookie, const std::string& name) {
    for (const auto& piece : split(cookie, "; ")) {
        const auto eq = piece.find('=');
        if (eq != std::string::npos && piece.compare(0, eq, name) == 0) return piece.substr(eq + 1);
    }
    return std::nullopt;
}
void set_cookie(std::string& cookie, const std::string& name, const std::string& value) {
    if (!cookie_name_valid(name) || !cookie_value_valid(value)) return;
    std::string out;
    for (const auto& piece : split(cookie, "; ")) {
        const auto eq = piece.find('=');
        if (eq == std::string::npos || piece.compare(0, eq, name) == 0) continue;
        if (!out.empty()) out += "; ";
        out += piece;
    }
    if (!out.empty()) out += "; ";
    cookie = out + name + "=" + value;
}
std::string safe_api_message(const std::string& text) {
    std::string lowered = text;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    for (const char* field : {"sessdata", "bili_jct", "qrcode_key", "cookie"}) {
        if (lowered.find(field) != std::string::npos) return "接口返回了凭据相关错误，敏感内容已隐藏";
    }
    std::string joined;
    for (const auto& word : split_words(text)) {
        if (!joined.empty()) joined += ' ';
        joined += word.find("://") != std::string::npos ? "[链接已隐藏]" : word;
    }
    std::u32string kept;
    for (const char32_t ch : decode(joined)) {
        if (ch >= 0x20 && ch != 0x7F && !(ch >= 0x80 && ch < 0xA0) && kept.size() < 160) kept.push_back(ch);
    }
    return encode(kept);
}
Json unwrap_api(const Json& value) {
    const int64_t code = value.is_object() && value.contains("code") && value["code"].is_number_integer() ? value["code"].get<int64_t>() : 0;
    if (code == -352 || code == -412) {
        set_cooldown(60);
        throw std::runtime_error("B 站触发风控（" + std::to_string(code) + "），已暂停后续请求 60 秒；请降低请求频率");
    }
    if (code != 0) {
        std::string message = "B 站接口返回错误";
        if (code == -101) message = "登录状态失效，请重新扫码登录";
        if (code == -400) message = "请求参数不正确";
        if (code == -403) message = "B 站拒绝了此请求";
        if (code == -404) message = "B 站内容不存在或不可见";
        std::string reason = str(value, "message");
        if (reason.empty()) reason = str(value, "msg");
        reason = safe_api_message(reason);
        message += "（错误码 " + std::to_string(code) + "）";
        if (!reason.empty()) message += "：" + reason;
        throw std::runtime_error(message);
    }
    if (value.is_object()) {
        if (value.contains("data")) return value["data"];
        if (value.contains("result")) return value["result"];
    }
    throw std::runtime_error("B 站响应缺少数据");
}
bool write_path_allowed(const std::string& path) {
    return path == "/x/v3/fav/resource/deal" || path == "/x/v2/history/toview/add" || path == "/x/v2/history/toview/del" ||
           path == "/x/click-interface/web/heartbeat";
}
static bool bilibili_host(const std::string& host) {
    static const std::string suffix = ".bilibili.com";
    return host == "bilibili.com" || (host.size() > suffix.size() && host.compare(host.size() - suffix.size(), suffix.size(), suffix) == 0);
}
bool qr_url_allowed(const std::string& raw) {
    UrlPtr url(curl_url());
    if (!url || curl_url_set(url.get(), CURLUPART_URL, raw.c_str(), 0) != CURLUE_OK) return false;
    return url_part(url.get(), CURLUPART_SCHEME) == "https" && url_part(url.get(), CURLUPART_USER).empty() &&
           url_part(url.get(), CURLUPART_PASSWORD).empty() && bilibili_host(url_part(url.get(), CURLUPART_HOST));
}
std::pair<int64_t, std::optional<std::string>> parse_qr_poll(const std::string& previous, const Json& value,
                                                             const std::vector<std::string>& set_cookies) {
    const Json data = unwrap_api(value);
    if (!data.is_object() || !data.contains("code") || !data["code"].is_number_integer()) throw std::runtime_error("B 站登录状态缺少 data.code");
    const int64_t state = data["code"].get<int64_t>();
    if (state != 0) return {state, std::nullopt};
    std::string issued;
    for (const auto& header : set_cookies) {
        const std::string pair = header.substr(0, header.find(';'));
        const auto eq = pair.find('=');
        if (eq != std::string::npos) set_cookie(issued, trim(pair.substr(0, eq)), trim(pair.substr(eq + 1)));
    }
    UrlPtr url(curl_url());
    const std::string raw = str(data, "url");
    if (url && !raw.empty() && curl_url_set(url.get(), CURLUPART_URL, raw.c_str(), 0) == CURLUE_OK) {
        const std::string host = url_part(url.get(), CURLUPART_HOST);
        if (url_part(url.get(), CURLUPART_SCHEME) == "https" && (host == "passport.bilibili.com" || host == "passport.biligame.com")) {
            for (const auto& piece : split(url_part(url.get(), CURLUPART_QUERY), "&")) {
                const auto eq = piece.find('=');
                if (eq == std::string::npos) continue;
                const std::string name = piece.substr(0, eq);
                if (name == "SESSDATA" || name == "bili_jct" || name == "DedeUserID" || name == "DedeUserID__ckMd5") {
                    set_cookie(issued, name, cookie_query_value(percent_decode(piece.substr(eq + 1))));
                }
            }
        }
    }
    if (cookie_value(issued, "SESSDATA").value_or("").empty() || cookie_value(issued, "bili_jct").value_or("").empty()) {
        throw std::runtime_error("登录成功响应未包含完整的新会话 cookie");
    }
    std::string cookies = clean_cookie(previous);
    for (const auto& piece : split(issued, "; ")) {
        const auto eq = piece.find('=');
        if (eq != std::string::npos) set_cookie(cookies, piece.substr(0, eq), piece.substr(eq + 1));
    }
    if (cookies.size() > 16384) throw std::runtime_error("B 站登录 cookie 超过 16 KiB 上限");
    return {state, cookies};
}
Api::Api(const std::string& cookie) : cookie_(clean_cookie(cookie)) {}
std::string Api::cookie() const {
    const std::lock_guard lock(mutex_);
    return cookie_;
}
bool Api::logged_in() const { return !cookie_value(cookie(), "SESSDATA").value_or("").empty(); }
std::optional<std::string> Api::user_id() const {
    auto id = cookie_value(cookie(), "DedeUserID");
    if (!id || id->empty() || !std::all_of(id->begin(), id->end(), [](unsigned char c) { return std::isdigit(c); })) return std::nullopt;
    return id;
}
Json Api::request(bool post, const std::string& host, const std::string& path, const Params& params, const std::string& csrf, bool use_cookie,
                  const CancelFlag& cancel, std::vector<std::string>* set_cookies) {
    validate_target(host, path);
    const uint64_t now = epoch();
    const uint64_t until = cooldown_until.load();
    if (until > now) throw std::runtime_error("B 站风控冷却中，还需等待 " + std::to_string(until - now) + " 秒");
    HttpRequest http;
    http.url = host + path;
    http.cancel = cancel;
    http.post = post;
    const std::string encoded = encode_params(params);
    if (post) {
        http.body = encoded;
        http.headers.emplace_back("Content-Type: application/x-www-form-urlencoded");
    } else if (!encoded.empty()) {
        http.url += "?" + encoded;
    }
    http.headers.emplace_back("Referer: https://www.bilibili.com/");
    const std::string jar = cookie();
    if (use_cookie && !jar.empty()) http.headers.push_back("Cookie: " + jar);
    if (!csrf.empty()) http.headers.push_back("x-csrf-token: " + csrf);
    HttpResponse response = http_perform(http);
    if (response.status == 412 || response.status == 429) {
        set_cooldown(60);
        throw std::runtime_error("B 站触发风控（HTTP " + std::to_string(response.status) + "），已暂停后续请求 60 秒；请稍后重试");
    }
    if (response.status < 200 || response.status >= 300) throw std::runtime_error("B 站请求失败（HTTP " + std::to_string(response.status) + "）");
    Json value = Json::parse(response.body, nullptr, false);
    if (value.is_discarded()) throw std::runtime_error("B 站返回了无效数据");
    if (value.is_object() && value.contains("code") && value["code"].is_number_integer()) {
        const int64_t code = value["code"].get<int64_t>();
        if (code == -352 || code == -412) {
            set_cooldown(60);
            throw std::runtime_error("B 站触发风控（" + std::to_string(code) + "），已暂停后续请求 60 秒；请降低请求频率");
        }
    }
    if (set_cookies) *set_cookies = std::move(response.set_cookies);
    return value;
}
void Api::initialize(const CancelFlag& cancel) {
    {
        const std::string jar = cookie();
        if (jar.find("buvid3=") != std::string::npos && jar.find("buvid4=") != std::string::npos) return;
    }
    const Json value = request(false, kApi, "/x/frontend/finger/spi", {}, "", false, cancel);
    if (!value.is_object() || !value.contains("data") || !value["data"].is_object()) throw std::runtime_error("B 站未返回设备标识");
    const std::lock_guard lock(mutex_);
    for (const auto& [field, name] : {std::pair{"b_3", "buvid3"}, std::pair{"b_4", "buvid4"}}) {
        const std::string item = str(value["data"], field);
        if (!item.empty() && item.size() < 256) set_cookie(cookie_, name, item);
    }
}
Json Api::get(const std::string& path, const Params& params, const CancelFlag& cancel) {
    return unwrap_api(request(false, kApi, path, params, "", true, cancel));
}
Json Api::signed_get(const std::string& path, const Params& params, const CancelFlag& cancel) {
    if (path.empty() || path[0] != '/' || path.find("/wbi/") == std::string::npos) throw std::runtime_error("WBI 请求路径无效");
    std::optional<std::pair<std::string, std::string>> keys;
    {
        const std::lock_guard lock(mutex_);
        keys = wbi_;
    }
    if (!keys) {
        // `/nav` still includes wbi_img when an anonymous request reports -101.
        const Json nav = request(false, kApi, "/x/web-interface/nav", {}, "", true, cancel);
        const int64_t code = nav.value("code", int64_t{0});
        if (code != 0 && code != -101) unwrap_api(nav);
        if (!nav.contains("data") || !nav["data"].is_object() || !nav["data"].contains("wbi_img")) throw std::runtime_error("B 站未提供 WBI 密钥");
        const Json& image = nav["data"]["wbi_img"];
        const auto img = key_from_url(str(image, "img_url"));
        const auto sub = key_from_url(str(image, "sub_url"));
        if (!img || !sub) throw std::runtime_error("B 站未提供有效 WBI 密钥");
        keys = std::make_pair(*img, *sub);
        const std::lock_guard lock(mutex_);
        wbi_ = keys;
    }
    return unwrap_api(request(false, kApi, path, wbi_sign(params, keys->first, keys->second, epoch()), "", true, cancel));
}
Json Api::post(const std::string& path, const Params& params, const CancelFlag& cancel) {
    if (!logged_in()) throw std::runtime_error("此操作需要先登录 B 站");
    if (!write_path_allowed(path)) throw std::runtime_error("该写入接口不在允许列表中");
    const std::string csrf = cookie_value(cookie(), "bili_jct").value_or("");
    if (csrf.empty()) throw std::runtime_error("登录状态缺少 CSRF 校验值");
    Params fields = params;
    fields.emplace_back("csrf", csrf);
    const Json value = request(true, kApi, path, fields, csrf, true, cancel);
    const Json data = value.value("code", int64_t{0}) == 0 ? Json(nullptr) : unwrap_api(value);
    return data;
}
std::vector<std::string> Api::suggest(const std::string& query, const CancelFlag& cancel) {
    std::vector<std::string> out;
    if (trim(query).empty() || query.size() > 128) return out;
    const Json value = request(false, kSearch, "/main/suggest", {{"term", query}, {"main_ver", "v1"}, {"highlight", ""}}, "", false, cancel);
    if (!value.is_object() || !value.contains("result") || !value["result"].is_object() || !value["result"].contains("tag")) return out;
    for (const Json& item : value["result"]["tag"]) {
        const std::string text = clean(str(item, "value"));
        if (!trim(text).empty() && out.size() < 20) out.push_back(text);
    }
    return out;
}
std::pair<std::string, std::string> Api::qr_generate(const CancelFlag& cancel) {
    const Json data = unwrap_api(request(false, kPassport, "/x/passport-login/web/qrcode/generate", {}, "", false, cancel));
    const std::string url = str(data, "url");
    if (!qr_url_allowed(url)) throw std::runtime_error("B 站返回的二维码链接无效：需要 HTTPS 的 bilibili.com 域名");
    const std::string key = str(data, "qrcode_key");
    if (!valid_qr_key(key)) throw std::runtime_error("B 站未返回有效二维码密钥");
    return {url, key};
}
std::pair<int64_t, std::optional<std::string>> Api::qr_poll(const std::string& key, const CancelFlag& cancel) {
    if (!valid_qr_key(key)) throw std::runtime_error("二维码密钥格式无效");
    std::vector<std::string> set_cookies;
    const Json value = request(false, kPassport, "/x/passport-login/web/qrcode/poll", {{"qrcode_key", key}}, "", false, cancel, &set_cookies);
    return parse_qr_poll(cookie(), value, set_cookies);
}
}  // namespace bili
