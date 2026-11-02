#include "model.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <nlohmann/json.hpp>
#include <stdexcept>

#include "ui/text.hpp"

using nlohmann::json;
namespace clash {
const char* message(ApiError error) {
    switch (error) {
        case ApiError::Transport: return "内核控制接口不可用";
        case ApiError::InvalidResponse: return "内核响应格式无效";
        case ApiError::Rejected: return "内核拒绝操作，请检查当前配置";
        case ApiError::InvalidEndpoint: return "控制接口地址无效";
    }
    return "";
}
namespace {
// Missing and null fields default. A present field of another type is an error, like serde.
std::string str(const json& node, const char* key) {
    const auto it = node.find(key);
    if (it == node.end() || it->is_null()) return {};
    return it->get<std::string>();
}
uint64_t num(const json& node, const char* key) {
    const auto it = node.find(key);
    if (it == node.end() || it->is_null()) return 0;
    if (!it->is_number_unsigned()) throw std::runtime_error("number");
    return it->get<uint64_t>();
}
bool flag(const json& node, const char* key) {
    const auto it = node.find(key);
    if (it == node.end() || it->is_null()) return false;
    return it->get<bool>();
}
std::vector<std::string> strings(const json& node, const char* key) {
    const auto it = node.find(key);
    if (it == node.end() || it->is_null()) return {};
    return it->get<std::vector<std::string>>();
}
const json& array_of(const json& node, const char* key) {
    static const json empty = json::array();
    const auto it = node.find(key);
    if (it == node.end() || it->is_null()) return empty;
    if (!it->is_array()) throw std::runtime_error("array");
    return *it;
}
Proxy proxy_of(const json& node) {
    Proxy out;
    out.name = str(node, "name");
    out.kind = str(node, "type");
    if (const auto it = node.find("now"); it != node.end() && !it->is_null()) out.now = it->get<std::string>();
    out.all = strings(node, "all");
    for (const json& sample : array_of(node, "history")) out.history.push_back({str(sample, "time"), num(sample, "delay")});
    return out;
}
json parse_object(std::string_view body) {
    json node = json::parse(body);
    if (!node.is_object()) throw std::runtime_error("object");
    return node;
}
}  // namespace
Proxies parse_proxies(std::string_view body) {
    const json root = parse_object(body);
    Proxies out;
    if (const auto it = root.find("proxies"); it != root.end() && !it->is_null()) {
        for (const auto& [name, value] : it->items()) out.emplace(name, proxy_of(value));
    }
    return out;
}
RuntimeConfig parse_config(std::string_view body) {
    const json root = parse_object(body);
    RuntimeConfig out;
    out.mode = str(root, "mode");
    if (const auto it = root.find("tun"); it != root.end() && !it->is_null()) out.tun = flag(*it, "enable");
    if (const auto it = root.find("mixed-port"); it != root.end() && !it->is_null()) {
        if (!it->is_number_unsigned() || it->get<uint64_t>() > 65535) throw std::runtime_error("port");
        out.mixed_port = static_cast<uint16_t>(it->get<uint64_t>());
    }
    return out;
}
std::string parse_version(std::string_view body) {
    const json root = parse_object(body);
    return (flag(root, "meta") ? "Meta " : "") + str(root, "version");
}
ConnectionsResponse parse_connections(std::string_view body) {
    const json root = parse_object(body);
    ConnectionsResponse out;
    // Mihomo encodes its nil slice as JSON null when no connection is active.
    for (const json& node : array_of(root, "connections")) {
        Connection row;
        row.id = str(node, "id");
        if (const auto it = node.find("metadata"); it != node.end() && !it->is_null()) {
            const json& meta = *it;
            row.metadata = {str(meta, "network"), str(meta, "host"), str(meta, "destinationIP"), str(meta, "destinationPort"),
                            str(meta, "sourceIP"), str(meta, "sourcePort"), str(meta, "process"), str(meta, "processPath")};
        }
        row.rule = str(node, "rule");
        row.rule_payload = str(node, "rulePayload");
        row.chains = strings(node, "chains");
        row.upload = num(node, "upload");
        row.download = num(node, "download");
        row.start = str(node, "start");
        out.connections.push_back(std::move(row));
    }
    out.upload_total = num(root, "uploadTotal");
    out.download_total = num(root, "downloadTotal");
    out.memory = num(root, "memory");
    return out;
}
Providers parse_providers(std::string_view body) {
    const json root = parse_object(body);
    Providers out;
    for (const auto& [name, node] : root.at("providers").items()) {
        Provider row;
        row.vehicle_type = str(node, "vehicleType");
        row.kind = str(node, "type");
        for (const json& proxy : array_of(node, "proxies")) row.proxies.push_back(proxy_of(proxy));
        row.updated_at = str(node, "updatedAt");
        row.rule_count = num(node, "ruleCount");
        out.emplace(name, std::move(row));
    }
    return out;
}
std::vector<Rule> parse_rules(std::string_view body) {
    const json root = parse_object(body);
    std::vector<Rule> out;
    for (const json& node : root.at("rules")) {
        Rule row;
        row.kind = str(node, "type");
        row.payload = str(node, "payload");
        row.proxy = str(node, "proxy");
        if (const auto it = node.find("extra"); it != node.end() && !it->is_null()) row.extra = RuleExtra{num(*it, "hitCount"), str(*it, "hitAt")};
        out.push_back(std::move(row));
    }
    return out;
}
std::map<std::string, uint64_t> parse_group_delay(std::string_view body) {
    std::map<std::string, uint64_t> out;
    for (const auto& [name, value] : parse_object(body).items()) {
        if (!value.is_number_unsigned()) throw std::runtime_error("delay");
        out.emplace(name, value.get<uint64_t>());
    }
    return out;
}
uint64_t parse_delay(std::string_view body) {
    const json root = parse_object(body);
    if (!root.at("delay").is_number_unsigned()) throw std::runtime_error("delay");
    return root.at("delay").get<uint64_t>();
}
LogEntry parse_log(std::string_view body) {
    const json root = parse_object(body);
    return LogEntry{0, str(root, "type"), str(root, "payload")};
}
Traffic parse_traffic(std::string_view body) {
    const json root = parse_object(body);
    if (!root.at("up").is_number_unsigned() || !root.at("down").is_number_unsigned()) throw std::runtime_error("traffic");
    return Traffic{root.at("up").get<uint64_t>(), root.at("down").get<uint64_t>(), num(root, "upTotal"), num(root, "downTotal")};
}

uint64_t Usage::used_bytes() const {
    const uint64_t sum = upload + download;
    return sum < upload ? UINT64_MAX : sum;
}
std::optional<uint64_t> Usage::remaining_bytes() const {
    if (total == 0) return std::nullopt;
    const uint64_t used = used_bytes();
    return used >= total ? 0 : total - used;
}
std::optional<double> Usage::progress() const {
    if (total == 0) return std::nullopt;
    return std::clamp(static_cast<double>(used_bytes()) / static_cast<double>(total), 0.0, 1.0);
}
std::optional<int64_t> Usage::expires_at() const {
    // chrono rejects timestamps past roughly year 262000, as the Rust version does.
    if (expire == 0 || expire > 8'210'298'412'799ULL) return std::nullopt;
    return static_cast<int64_t>(expire);
}
std::optional<Usage> Usage::from_header(std::string_view header) {
    Usage usage;
    bool recognized = false;
    size_t at = 0;
    while (at <= header.size()) {
        const size_t end = std::min(header.find(';', at), header.size());
        const std::string field = tui::trim(header.substr(at, end - at));
        at = end + 1;
        if (field.empty()) continue;
        const auto equal = field.find('=');
        if (equal == std::string::npos) return std::nullopt;
        std::string key = tui::trim(std::string_view(field).substr(0, equal));
        std::transform(key.begin(), key.end(), key.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
        uint64_t* slot = key == "upload" ? &usage.upload : key == "download" ? &usage.download : key == "total" ? &usage.total : key == "expire" ? &usage.expire : nullptr;
        if (!slot) continue;
        const std::string value = tui::trim(std::string_view(field).substr(equal + 1));
        const auto [ptr, error] = std::from_chars(value.data(), value.data() + value.size(), *slot);
        if (error != std::errc{} || ptr != value.data() + value.size() || value.empty()) return std::nullopt;
        recognized = true;
    }
    if (!recognized) return std::nullopt;
    return usage;
}

namespace {
constexpr char kHex[] = "0123456789ABCDEF";
void percent(std::string& out, unsigned char c) {
    out += '%';
    out += kHex[c >> 4];
    out += kHex[c & 15];
}
bool alnum(unsigned char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); }
// Encodes bytes in `set`, controls and everything outside ASCII; existing escapes stay.
std::string encode_part(std::string_view text, std::string_view set) {
    std::string out;
    for (const char raw : text) {
        const auto c = static_cast<unsigned char>(raw);
        if (c <= 0x20 || c >= 0x7F || set.find(raw) != std::string_view::npos) percent(out, c);
        else out += raw;
    }
    return out;
}
std::string normalize_path(std::string_view path) {
    std::vector<std::string> kept;
    size_t at = path.empty() ? std::string_view::npos : 1;
    bool trailing = path.empty();
    while (at != std::string_view::npos) {
        const auto slash = path.find('/', at);
        const std::string_view part = path.substr(at, slash == std::string_view::npos ? slash : slash - at);
        const bool last = slash == std::string_view::npos;
        std::string lower(part);
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
        if (lower == ".." || lower == ".%2e" || lower == "%2e." || lower == "%2e%2e") {
            if (!kept.empty()) kept.pop_back();
            trailing = last;
        } else if (lower == "." || lower == "%2e") {
            trailing = last;
        } else {
            kept.emplace_back(part);
            trailing = false;
        }
        at = last ? std::string_view::npos : slash + 1;
    }
    std::string out;
    for (const auto& part : kept) out += "/" + part;
    if (trailing || out.empty()) out += "/";
    return out;
}
}  // namespace
std::optional<Url> parse_url(std::string_view raw) {
    // Same cleanup as a browser-style parser: outer controls and spaces, inner tabs and newlines.
    while (!raw.empty() && static_cast<unsigned char>(raw.front()) <= 0x20) raw.remove_prefix(1);
    while (!raw.empty() && static_cast<unsigned char>(raw.back()) <= 0x20) raw.remove_suffix(1);
    std::string text;
    for (const char c : raw) {
        if (c != '\t' && c != '\n' && c != '\r') text += c;
    }
    const auto colon = text.find(':');
    if (colon == std::string::npos) return std::nullopt;
    std::string scheme = text.substr(0, colon);
    std::transform(scheme.begin(), scheme.end(), scheme.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
    if (scheme != "http" && scheme != "https") return std::nullopt;
    size_t at = colon + 1;
    while (at < text.size() && (text[at] == '/' || text[at] == '\\')) ++at;
    const size_t end = std::min(text.find_first_of("/\\?#", at), text.size());
    std::string authority = text.substr(at, end - at);
    std::string user;
    if (const auto mark = authority.rfind('@'); mark != std::string::npos) {
        user = encode_part(authority.substr(0, mark), "\"#<>?`{}/;=@[\\]^|");
        authority.erase(0, mark + 1);
    }
    std::string host = authority;
    std::string port;
    if (const auto bracket = authority.find(']'); !authority.empty() && authority[0] == '[') {
        if (bracket == std::string::npos) return std::nullopt;
        host = authority.substr(0, bracket + 1);
        if (bracket + 1 < authority.size()) {
            if (authority[bracket + 1] != ':') return std::nullopt;
            port = authority.substr(bracket + 2);
        }
    } else if (const auto mark = authority.rfind(':'); mark != std::string::npos) {
        host = authority.substr(0, mark);
        port = authority.substr(mark + 1);
    }
    if (host.empty()) return std::nullopt;
    for (char& c : host) {
        const auto byte = static_cast<unsigned char>(c);
        // Internationalized hosts need IDNA, which the program does not carry; they are refused, not guessed.
        if (byte <= 0x20 || byte >= 0x7F || std::string_view("#%/<>?@\\^|").find(c) != std::string_view::npos) return std::nullopt;
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(byte + 32);
    }
    if (!port.empty()) {
        unsigned value = 0;
        const auto [ptr, error] = std::from_chars(port.data(), port.data() + port.size(), value);
        if (error != std::errc{} || ptr != port.data() + port.size() || value > 65535) return std::nullopt;
        port = (scheme == "http" && value == 80) || (scheme == "https" && value == 443) ? "" : std::to_string(value);
    }
    size_t rest = end;
    const size_t path_end = std::min(text.find_first_of("?#", rest), text.size());
    std::string path = text.substr(rest, path_end - rest);
    std::replace(path.begin(), path.end(), '\\', '/');
    std::string out = scheme + "://";
    if (!user.empty()) out += user + "@";
    out += host;
    if (!port.empty()) out += ":" + port;
    out += normalize_path(encode_part(path, "\"<>`#?{}"));
    rest = path_end;
    if (rest < text.size() && text[rest] == '?') {
        const size_t query_end = std::min(text.find('#', rest), text.size());
        out += "?" + encode_part(std::string_view(text).substr(rest + 1, query_end - rest - 1), "\"<>#'");
        rest = query_end;
    }
    if (rest < text.size() && text[rest] == '#') out += "#" + encode_part(std::string_view(text).substr(rest + 1), "\"<>`");
    return Url{scheme, host, out};
}
std::string redact_url(std::string_view raw) {
    if (const auto url = parse_url(raw)) return url->scheme + "://" + url->host + "/…";
    return raw.empty() ? "等待粘贴" : "地址内容隐藏";
}
std::string encode_segment(std::string_view segment) {
    std::string out;
    for (const char raw : segment) {
        const auto c = static_cast<unsigned char>(raw);
        if (alnum(c) || std::string_view("-._~!$&'()*+,;=:@").find(raw) != std::string_view::npos) out += raw;
        else percent(out, c);
    }
    return out;
}
std::string encode_path(const std::vector<std::string>& segments) {
    std::string out;
    for (const std::string& segment : segments) {
        // A remote name must never climb out of its route.
        if (segment == "." || segment == "..") continue;
        out += "/" + encode_segment(segment);
    }
    return out.empty() ? "/" : out;
}
std::string encode_query(std::string_view value) {
    std::string out;
    for (const char raw : value) {
        const auto c = static_cast<unsigned char>(raw);
        if (alnum(c) || raw == '*' || raw == '-' || raw == '.' || raw == '_') out += raw;
        else if (raw == ' ') out += '+';
        else percent(out, c);
    }
    return out;
}

bool is_control(char32_t ch) { return ch < 0x20 || (ch >= 0x7F && ch < 0xA0); }
bool is_space(char32_t ch) {
    return (ch >= 9 && ch <= 13) || ch == 0x20 || ch == 0x85 || ch == 0xA0 || ch == 0x1680 || (ch >= 0x2000 && ch <= 0x200A) || ch == 0x2028 || ch == 0x2029 || ch == 0x202F || ch == 0x205F || ch == 0x3000;
}
std::vector<std::string> unicode_words(std::string_view text) {
    std::vector<std::string> out;
    std::string word;
    for (const char32_t ch : tui::decode(text)) {
        if (is_space(ch)) {
            if (!word.empty()) out.push_back(std::exchange(word, {}));
        } else {
            tui::append(word, ch);
        }
    }
    if (!word.empty()) out.push_back(std::move(word));
    return out;
}
std::string redact_log(std::string_view text) {
    std::string out;
    for (const std::string& word : unicode_words(text)) {
        std::string lower = word;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
        if (!out.empty()) out += ' ';
        const bool hide = word.find("://") != std::string::npos || lower.find("token=") != std::string::npos || lower.find("secret=") != std::string::npos;
        out += hide ? "[链接/凭据已隐藏]" : word;
    }
    return out;
}
std::string safe_name(std::string_view raw) {
    std::string kept;
    size_t count = 0;
    for (const char32_t ch : tui::decode(raw)) {
        if (is_control(ch)) continue;
        if (count++ == 100) break;
        tui::append(kept, ch);
    }
    return redact_log(kept);
}
std::string strip_controls(std::string_view text) {
    bool clean = true;
    for (size_t i = 0; i < text.size() && clean; ++i) {
        const auto c = static_cast<unsigned char>(text[i]);
        clean = c >= 0x20 && c != 0x7F && !(c == 0xC2 && i + 1 < text.size() && static_cast<unsigned char>(text[i + 1]) < 0xA0);
    }
    if (clean) return std::string(text);
    std::string out;
    for (const char32_t ch : tui::decode(text)) {
        if (!is_control(ch)) tui::append(out, ch);
    }
    return out;
}

std::string bytes_text(uint64_t value) {
    auto size = static_cast<double>(value);
    const char* unit = "B";
    for (const char* next : {"KiB", "MiB", "GiB", "TiB"}) {
        if (size < 1024.0) break;
        size /= 1024.0;
        unit = next;
    }
    char buffer[48];
    std::snprintf(buffer, sizeof buffer, "%.1f %s", size, unit);
    return buffer;
}
std::optional<int64_t> rfc3339_seconds(std::string_view text) {
    // YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM)
    if (text.size() < 20 || text[4] != '-' || text[7] != '-' || (text[10] != 'T' && text[10] != 't') || text[13] != ':' || text[16] != ':') return std::nullopt;
    const auto field = [&](size_t at, size_t length) -> std::optional<int> {
        int value = 0;
        const auto [ptr, error] = std::from_chars(text.data() + at, text.data() + at + length, value);
        if (error != std::errc{} || ptr != text.data() + at + length) return std::nullopt;
        return value;
    };
    const auto year = field(0, 4), month = field(5, 2), day = field(8, 2), hour = field(11, 2), minute = field(14, 2), second = field(17, 2);
    if (!year || !month || !day || !hour || !minute || !second || *month < 1 || *month > 12 || *day < 1 || *day > 31 || *hour > 23 || *minute > 59 || *second > 60) return std::nullopt;
    size_t at = 19;
    if (text[at] == '.') {
        ++at;
        const size_t digits = at;
        while (at < text.size() && text[at] >= '0' && text[at] <= '9') ++at;
        if (at == digits) return std::nullopt;
    }
    if (at >= text.size()) return std::nullopt;
    int offset = 0;
    if (text[at] == 'Z' || text[at] == 'z') {
        if (at + 1 != text.size()) return std::nullopt;
    } else if ((text[at] == '+' || text[at] == '-') && at + 6 == text.size() && text[at + 3] == ':') {
        const auto hours = field(at + 1, 2), minutes = field(at + 4, 2);
        if (!hours || !minutes) return std::nullopt;
        offset = (*hours * 3600 + *minutes * 60) * (text[at] == '-' ? -1 : 1);
    } else {
        return std::nullopt;
    }
    std::tm parts{};
    parts.tm_year = *year - 1900;
    parts.tm_mon = *month - 1;
    parts.tm_mday = *day;
    parts.tm_hour = *hour;
    parts.tm_min = *minute;
    parts.tm_sec = *second;
    return static_cast<int64_t>(timegm(&parts)) - offset;
}
std::string age_text(std::string_view start) {
    const auto when = rfc3339_seconds(start);
    if (!when) return "--";
    const int64_t seconds = std::max<int64_t>(unix_now() - *when, 0);
    if (seconds < 60) return std::to_string(seconds) + "s";
    if (seconds < 3600) return std::to_string(seconds / 60) + "m";
    return std::to_string(seconds / 3600) + "h";
}
std::string local_time(int64_t epoch, const char* format) {
    const auto when = static_cast<time_t>(epoch);
    std::tm local{};
    if (!localtime_r(&when, &local)) return {};
    char buffer[64];
    return std::strftime(buffer, sizeof buffer, format, &local) ? buffer : "";
}
int64_t unix_now() { return std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }
std::string base64_decode(std::string_view text, bool& ok) {
    // Standard alphabet with mandatory padding, as the Rust version requires.
    ok = false;
    if (text.size() % 4 != 0) return {};
    std::string out;
    uint32_t bits = 0;
    int have = 0;
    size_t padding = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        int value = -1;
        if (c >= 'A' && c <= 'Z') value = c - 'A';
        else if (c >= 'a' && c <= 'z') value = c - 'a' + 26;
        else if (c >= '0' && c <= '9') value = c - '0' + 52;
        else if (c == '+') value = 62;
        else if (c == '/') value = 63;
        else if (c == '=' && i + 2 >= text.size()) { ++padding; continue; }
        if (value < 0 || padding > 0) return {};
        bits = (bits << 6) | static_cast<uint32_t>(value);
        have += 6;
        if (have >= 8) {
            have -= 8;
            out += static_cast<char>((bits >> have) & 255);
        }
    }
    if (have > 0 && (bits & ((1U << have) - 1)) != 0) return {};
    ok = true;
    return out;
}
}  // namespace clash
