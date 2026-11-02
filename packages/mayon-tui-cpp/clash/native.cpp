#include "native.hpp"

#include <curl/curl.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <poll.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <yaml-cpp/yaml.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <fstream>
#include <memory>
#include <set>
#include <sstream>
#include <toml++/toml.hpp>

#include "api.hpp"
#include "ui/text.hpp"

namespace fs = std::filesystem;
namespace clash {
namespace {
constexpr size_t kMaxBody = 32 * 1024 * 1024;
const std::unexpected<std::string> fail(std::string text) { return std::unexpected(std::move(text)); }
int64_t now_nanos() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }

// ---- Files -------------------------------------------------------------------------------------
std::optional<std::string> read_file(const fs::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return std::nullopt;
    std::ostringstream out;
    out << in.rdbuf();
    if (in.bad()) return std::nullopt;
    return std::move(out).str();
}
bool write_all(int fd, std::string_view bytes) {
    while (!bytes.empty()) {
        const ssize_t wrote = ::write(fd, bytes.data(), bytes.size());
        if (wrote < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        bytes.remove_prefix(static_cast<size_t>(wrote));
    }
    return true;
}
struct Temp {
    fs::path path;
    Temp() = default;
    Temp(Temp&& other) noexcept : path(std::exchange(other.path, {})) {}
    Temp& operator=(Temp&&) = delete;
    ~Temp() {
        if (!path.empty()) {
            std::error_code ignored;
            fs::remove(path, ignored);
        }
    }
};
Res<Temp> stage(const fs::path& target, std::string_view bytes) {
    fs::path name = target;
    name.replace_extension("tmp-" + std::to_string(getpid()) + "-" + std::to_string(now_nanos()));
    const int fd = ::open(name.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) return fail("无法创建临时文件");
    Temp temp;
    temp.path = name;
    const bool ok = write_all(fd, bytes) && ::fsync(fd) == 0;
    ::close(fd);
    if (!ok) return fail("无法写入临时文件");
    return temp;
}
// ---- Processes ---------------------------------------------------------------------------------
struct Ran {
    bool success = false;
    std::string output;
};
Ran run_process(const std::vector<std::string>& argv, bool capture, bool filter, int timeout_ms) {
    std::vector<char*> args;
    for (const auto& arg : argv) args.push_back(const_cast<char*>(arg.c_str()));
    args.push_back(nullptr);
    int pipes[2] = {-1, -1};
    if (capture && ::pipe2(pipes, O_CLOEXEC) != 0) return {};
    const int null = ::open("/dev/null", O_RDWR | O_CLOEXEC);
    const pid_t child = ::fork();
    if (child < 0) {
        if (capture) {
            ::close(pipes[0]);
            ::close(pipes[1]);
        }
        if (null >= 0) ::close(null);
        return {};
    }
    if (child == 0) {
        // Only async-signal-safe calls from here: other threads may hold any lock.
        ::dup2(null, 0);
        ::dup2(capture ? pipes[1] : null, 1);
        ::dup2(null, 2);
        ::syscall(SYS_close_range, 3U, ~0U, 0U);
        if (filter && !validation_network_filter()) ::_exit(126);
        ::execvp(args[0], args.data());
        ::_exit(127);
    }
    if (null >= 0) ::close(null);
    if (capture) ::close(pipes[1]);
    const int pidfd = static_cast<int>(::syscall(SYS_pidfd_open, child, 0));
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
    Ran out;
    bool exited = false;
    bool open = capture;
    bool timed_out = false;
    // Sleeps on the child and its pipe; nothing here spins.
    while (!exited || open) {
        const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now()).count();
        if (left <= 0) {
            timed_out = true;
            break;
        }
        pollfd items[2]{{exited ? -1 : pidfd, POLLIN, 0}, {open ? pipes[0] : -1, POLLIN, 0}};
        const int ready = ::poll(items, 2, static_cast<int>(std::min<long long>(left, pidfd < 0 ? 100 : left)));
        if (ready < 0 && errno != EINTR) break;
        if (pidfd < 0 || (items[0].revents & POLLIN)) {
            int ignored = 0;
            const pid_t done = ::waitpid(child, &ignored, WNOHANG);
            if (done == child) {
                exited = true;
                out.success = WIFEXITED(ignored) && WEXITSTATUS(ignored) == 0;
            }
        }
        if (open && (items[1].revents & (POLLIN | POLLHUP))) {
            char buffer[8192];
            const ssize_t got = ::read(pipes[0], buffer, sizeof buffer);
            if (got > 0 && out.output.size() < 1024 * 1024) out.output.append(buffer, static_cast<size_t>(got));
            if (got <= 0) open = false;
        }
    }
    if (!exited) {
        ::kill(child, SIGKILL);
        int status = 0;
        ::waitpid(child, &status, 0);
        if (!timed_out) out.success = WIFEXITED(status) && WEXITSTATUS(status) == 0;
    }
    if (timed_out) out.success = false;
    if (pidfd >= 0) ::close(pidfd);
    if (capture) ::close(pipes[0]);
    return out;
}

// ---- TOML --------------------------------------------------------------------------------------
std::string toml_string(std::string_view text) {
    std::string out = "\"";
    for (const char c : text) {
        const auto byte = static_cast<unsigned char>(c);
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\t': out += "\\t"; break;
            case '\r': out += "\\r"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (byte < 0x20 || byte == 0x7F) {
                    char buffer[8];
                    std::snprintf(buffer, sizeof buffer, "\\u%04X", byte);
                    out += buffer;
                } else {
                    out += c;
                }
        }
    }
    return out + "\"";
}
// TOML integers are signed; a value past that cannot be stored, same as the Rust encoder.
Res<std::string> toml_uint(uint64_t value) {
    if (value > static_cast<uint64_t>(INT64_MAX)) return fail("数据编码失败");
    return std::to_string(value);
}
const std::unexpected<std::string> kBadData = fail("本地数据格式无效（内容隐藏）");
// Field readers: absent gives nothing, a present field of the wrong type is an error.
bool read_string(const toml::table& table, const char* key, std::optional<std::string>& out) {
    const toml::node* node = table.get(key);
    if (!node) return true;
    const auto* value = node->as_string();
    if (!value) return false;
    out = value->get();
    return true;
}
bool read_bool(const toml::table& table, const char* key, std::optional<bool>& out) {
    const toml::node* node = table.get(key);
    if (!node) return true;
    const auto* value = node->as_boolean();
    if (!value) return false;
    out = value->get();
    return true;
}
bool read_int(const toml::table& table, const char* key, std::optional<int64_t>& out) {
    const toml::node* node = table.get(key);
    if (!node) return true;
    const auto* value = node->as_integer();
    if (!value) return false;
    out = value->get();
    return true;
}
bool read_uint(const toml::table& table, const char* key, std::optional<uint64_t>& out) {
    std::optional<int64_t> value;
    if (!read_int(table, key, value)) return false;
    if (value) {
        if (*value < 0) return false;
        out = static_cast<uint64_t>(*value);
    }
    return true;
}
std::optional<toml::table> parse_toml(std::string_view text) {
    try {
        return toml::parse(text);
    } catch (const toml::parse_error&) {
        return std::nullopt;
    }
}

// ---- YAML --------------------------------------------------------------------------------------
// yaml-cpp's own Node emitter drops the quotes of "123" and turns it into a number, so a quoted password
// would change type. This walker keeps quoted scalars quoted and expands aliases as serde_yaml does.
struct YamlBudget {
    size_t nodes = 0;
};
constexpr size_t kMaxYamlNodes = 8'000'000;
constexpr int kMaxYamlDepth = 128;
bool emit_yaml(YAML::Emitter& out, const YAML::Node& node, YamlBudget& budget, int depth) {
    if (++budget.nodes > kMaxYamlNodes || depth > kMaxYamlDepth) return false;
    switch (node.Type()) {
        case YAML::NodeType::Null:
        case YAML::NodeType::Undefined:
            out << YAML::Null;
            return true;
        case YAML::NodeType::Scalar:
            if (node.Tag() == "!") out << YAML::DoubleQuoted << node.Scalar();
            else out << node.Scalar();
            return true;
        case YAML::NodeType::Sequence:
            out << YAML::BeginSeq;
            for (const auto& item : node) {
                if (!emit_yaml(out, item, budget, depth + 1)) return false;
            }
            out << YAML::EndSeq;
            return true;
        case YAML::NodeType::Map:
            out << YAML::BeginMap;
            for (const auto& item : node) {
                out << YAML::Key;
                if (!emit_yaml(out, item.first, budget, depth + 1)) return false;
                out << YAML::Value;
                if (!emit_yaml(out, item.second, budget, depth + 1)) return false;
            }
            out << YAML::EndMap;
            return true;
    }
    return false;
}
// serde_yaml refuses duplicate keys, so the same document must fail here too.
bool no_duplicate_keys(const YAML::Node& node, YamlBudget& budget, int depth) {
    if (++budget.nodes > kMaxYamlNodes || depth > kMaxYamlDepth) return false;
    if (node.IsSequence()) {
        for (const auto& item : node) {
            if (!no_duplicate_keys(item, budget, depth + 1)) return false;
        }
    } else if (node.IsMap()) {
        std::set<std::string> seen;
        for (const auto& item : node) {
            if (item.first.IsScalar() && !seen.insert(item.first.Scalar()).second) return false;
            if (!no_duplicate_keys(item.second, budget, depth + 1)) return false;
        }
    }
    return true;
}
bool valid_utf8(std::string_view text) {
    for (const char32_t ch : tui::decode(text)) {
        if (ch == U'�') {
            if (text.find("\xEF\xBF\xBD") == std::string_view::npos) return false;
        }
    }
    // A replacement character is only legitimate where the source really holds one.
    size_t real = 0;
    for (size_t at = 0; (at = text.find("\xEF\xBF\xBD", at)) != std::string_view::npos; at += 3) ++real;
    size_t decoded = 0;
    for (const char32_t ch : tui::decode(text)) decoded += ch == U'�';
    return decoded == real;
}
std::optional<YAML::Node> load_yaml(std::string_view bytes) {
    if (!valid_utf8(bytes)) return std::nullopt;
    try {
        std::vector<YAML::Node> documents = YAML::LoadAll(std::string(bytes));
        if (documents.size() > 1) return std::nullopt;
        YAML::Node root = documents.empty() ? YAML::Node() : documents.front();
        YamlBudget budget;
        if (!no_duplicate_keys(root, budget, 0)) return std::nullopt;
        return root;
    } catch (const std::exception&) {
        return std::nullopt;
    }
}
bool is_map(const YAML::Node& parent, const char* key) { return parent.IsMap() && parent[key].IsDefined() && parent[key].IsMap(); }
bool is_missing(const YAML::Node& parent, const char* key) {
    if (!parent[key].IsDefined()) return true;
    return parent[key].IsNull();
}
std::string lower(std::string_view text) {
    std::string out(text);
    std::transform(out.begin(), out.end(), out.begin(), [](unsigned char c) { return static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c); });
    return out;
}

// ---- Network -----------------------------------------------------------------------------------
struct Fetched {
    long status = 0;
    Headers headers;
    std::string body;
    bool too_large = false;
    bool headers_done = false;
};
struct FetchOptions {
    std::string url;
    std::optional<std::string> proxy;
    long timeout_ms = 25000;
    long redirects = 0;
    const char* user_agent = nullptr;
    bool head = false;
    bool stop_after_headers = false;
};
size_t on_header(char* data, size_t size, size_t count, void* user) {
    auto* context = static_cast<std::pair<Fetched*, const FetchOptions*>*>(user);
    Fetched& out = *context->first;
    const size_t total = size * count;
    std::string_view line(data, total);
    if (line.rfind("HTTP/", 0) == 0) {
        // Each redirect hop starts over; only the final response counts.
        out.headers.clear();
        out.headers_done = false;
        const auto space = line.find(' ');
        out.status = space == std::string_view::npos ? 0 : std::atol(std::string(line.substr(space + 1, 3)).c_str());
        return total;
    }
    if (line == "\r\n" || line == "\n") {
        out.headers_done = true;
        // Without reading the body: a clean stop as soon as the headers are complete.
        const bool informational = out.status >= 100 && out.status < 200;
        if (context->second->stop_after_headers && !informational) return 0;
        return total;
    }
    const auto colon = line.find(':');
    if (colon != std::string_view::npos) out.headers.emplace_back(lower(line.substr(0, colon)), tui::trim(line.substr(colon + 1)));
    return total;
}
size_t on_body(char* data, size_t size, size_t count, void* user) {
    auto* out = static_cast<Fetched*>(user);
    const size_t total = size * count;
    if (out->body.size() + total > kMaxBody) {
        out->too_large = true;
        return 0;
    }
    out->body.append(data, total);
    return total;
}
// False on a transport failure. Error strings are deliberately not read: they can quote the URL.
bool fetch(const FetchOptions& options, Fetched& out) {
    const std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl) return false;
    CURL* handle = curl.get();
    std::pair<Fetched*, const FetchOptions*> context{&out, &options};
    curl_easy_setopt(handle, CURLOPT_URL, options.url.c_str());
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, options.timeout_ms);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, options.redirects > 0 ? 1L : 0L);
    curl_easy_setopt(handle, CURLOPT_MAXREDIRS, options.redirects);
    curl_easy_setopt(handle, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(handle, CURLOPT_HEADERDATA, &context);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &out);
    curl_easy_setopt(handle, CURLOPT_MAXFILESIZE_LARGE, static_cast<curl_off_t>(kMaxBody));
    curl_easy_setopt(handle, CURLOPT_SUPPRESS_CONNECT_HEADERS, 1L);
    if (options.user_agent) curl_easy_setopt(handle, CURLOPT_USERAGENT, options.user_agent);
    if (options.head) curl_easy_setopt(handle, CURLOPT_NOBODY, 1L);
    // Environment proxies are ignored; an explicit one applies to every host including loopback.
    curl_easy_setopt(handle, CURLOPT_PROXY, options.proxy ? options.proxy->c_str() : "");
    curl_easy_setopt(handle, CURLOPT_NOPROXY, "");
    const CURLcode code = curl_easy_perform(handle);
    if (code == CURLE_FILESIZE_EXCEEDED) out.too_large = true;
    if (options.stop_after_headers && out.headers_done && out.status >= 200) return true;
    return code == CURLE_OK || out.too_large;
}
std::optional<std::string> header_value(const Headers& headers, const std::string& name) {
    for (const auto& [key, value] : headers) {
        if (key == name) return value;
    }
    return std::nullopt;
}
// reqwest's to_str: visible ASCII only.
bool visible_ascii(std::string_view text) {
    return std::all_of(text.begin(), text.end(), [](unsigned char c) { return c == '\t' || (c >= 0x20 && c < 0x7F); });
}
std::string percent_decode(std::string_view raw) {
    std::string out;
    const auto hex = [](char c) { return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1; };
    for (size_t i = 0; i < raw.size(); ++i) {
        if (raw[i] != '%') {
            out += raw[i];
        } else if (i + 2 < raw.size() + 0 && i + 2 <= raw.size() - 1) {
            const int high = hex(raw[i + 1]), low = hex(raw[i + 2]);
            if (high >= 0 && low >= 0) out += static_cast<char>(high * 16 + low);
            i += 2;
        } else {
            break;
        }
    }
    return tui::encode(tui::decode(out));
}
std::string_view trim_quotes(std::string_view text) {
    while (!text.empty() && text.front() == '"') text.remove_prefix(1);
    while (!text.empty() && text.back() == '"') text.remove_suffix(1);
    return text;
}
}  // namespace

// ---- Settings and index ------------------------------------------------------------------------
Res<> Settings::set(std::string_view key, std::string_view value) {
    const auto boolean = [&]() -> Res<bool> {
        if (value == "true") return true;
        if (value == "false") return false;
        return fail("请输入 true 或 false");
    };
    if (key == "tun" || key == "ipv6" || key == "allow-lan") {
        const auto parsed = boolean();
        if (!parsed) return std::unexpected(parsed.error());
        (key == "tun" ? tun : key == "ipv6" ? ipv6 : allow_lan) = *parsed;
        return {};
    }
    if (key == "mode" && (value == "rule" || value == "global" || value == "direct")) {
        mode = value;
        return {};
    }
    if (key == "log-level" && (value == "silent" || value == "error" || value == "warning" || value == "info" || value == "debug")) {
        log_level = value;
        return {};
    }
    if (key == "mixed-port") {
        unsigned parsed = 0;
        const auto [ptr, error] = std::from_chars(value.data(), value.data() + value.size(), parsed);
        if (error != std::errc{} || ptr != value.data() + value.size() || parsed == 0 || parsed > 65535) return fail("端口范围 1–65535");
        mixed_port = static_cast<uint16_t>(parsed);
        return {};
    }
    return fail("设置名称或取值无效");
}
std::vector<std::string> Store::due() const {
    const int64_t now = unix_now();
    std::vector<std::string> out;
    for (const Subscription& item : items) {
        const auto hours = static_cast<int64_t>(std::clamp<uint64_t>(item.interval_hours, 1, 8760));
        if (now - item.updated >= hours * 3600) out.push_back(item.id);
    }
    return out;
}
Res<std::string> encode_store(const Store& store) {
    std::string out;
    if (store.current) out += "current = " + toml_string(*store.current) + "\n";
    if (store.items.empty()) out += "items = []\n";
    for (const Subscription& item : store.items) {
        if (!out.empty()) out += "\n";
        out += "[[items]]\n";
        out += "id = " + toml_string(item.id) + "\n";
        out += "name = " + toml_string(item.name) + "\n";
        out += "url = " + toml_string(item.url) + "\n";
        out += "updated = " + std::to_string(item.updated) + "\n";
        const auto interval = toml_uint(item.interval_hours);
        const auto nodes = toml_uint(item.nodes);
        if (!interval || !nodes) return fail("数据编码失败");
        out += "interval_hours = " + *interval + "\n";
        out += "nodes = " + *nodes + "\n";
        out += std::string("verge_current = ") + (item.legacy_current_marker ? "true" : "false") + "\n";
        if (item.usage) {
            const auto upload = toml_uint(item.usage->upload), download = toml_uint(item.usage->download), total = toml_uint(item.usage->total), expire = toml_uint(item.usage->expire);
            if (!upload || !download || !total || !expire) return fail("数据编码失败");
            out += "\n[items.usage]\nupload = " + *upload + "\ndownload = " + *download + "\ntotal = " + *total + "\nexpire = " + *expire + "\n";
        }
    }
    return out;
}
Res<std::string> encode_settings(const Settings& settings) {
    std::string out;
    out += std::string("tun = ") + (settings.tun ? "true" : "false") + "\n";
    out += "mode = " + toml_string(settings.mode) + "\n";
    out += std::string("ipv6 = ") + (settings.ipv6 ? "true" : "false") + "\n";
    out += std::string("allow_lan = ") + (settings.allow_lan ? "true" : "false") + "\n";
    out += "log_level = " + toml_string(settings.log_level) + "\n";
    out += "mixed_port = " + std::to_string(settings.mixed_port) + "\n";
    out += "baseline = " + toml_string(settings.baseline) + "\n";
    return out;
}
Res<Store> decode_store(std::string_view text) {
    const auto parsed = parse_toml(text);
    if (!parsed) return kBadData;
    Store store;
    if (!read_string(*parsed, "current", store.current)) return kBadData;
    const toml::node* items = parsed->get("items");
    if (!items) return store;
    const toml::array* list = items->as_array();
    if (!list) return kBadData;
    for (const toml::node& node : *list) {
        const toml::table* row = node.as_table();
        if (!row) return kBadData;
        std::optional<std::string> id, name, url;
        std::optional<int64_t> updated;
        std::optional<uint64_t> interval, nodes;
        std::optional<bool> marker;
        if (!read_string(*row, "id", id) || !read_string(*row, "name", name) || !read_string(*row, "url", url) || !read_int(*row, "updated", updated) ||
            !read_uint(*row, "interval_hours", interval) || !read_uint(*row, "nodes", nodes) || !read_bool(*row, "verge_current", marker)) return kBadData;
        if (!id || !name || !url || !updated || !interval || !nodes) return kBadData;
        Subscription item{*id, *name, *url, *updated, *interval, std::nullopt, *nodes, marker.value_or(false)};
        if (const toml::node* usage = row->get("usage")) {
            const toml::table* fields = usage->as_table();
            if (!fields) return kBadData;
            std::optional<uint64_t> upload, download, total, expire;
            if (!read_uint(*fields, "upload", upload) || !read_uint(*fields, "download", download) || !read_uint(*fields, "total", total) || !read_uint(*fields, "expire", expire)) return kBadData;
            item.usage = Usage{upload.value_or(0), download.value_or(0), total.value_or(0), expire.value_or(0)};
        }
        store.items.push_back(std::move(item));
    }
    return store;
}
Res<Settings> decode_settings(std::string_view text) {
    const auto parsed = parse_toml(text);
    if (!parsed) return kBadData;
    Settings settings;
    std::optional<bool> tun, ipv6, allow_lan;
    std::optional<std::string> mode, log_level, baseline;
    std::optional<uint64_t> port;
    if (!read_bool(*parsed, "tun", tun) || !read_bool(*parsed, "ipv6", ipv6) || !read_bool(*parsed, "allow_lan", allow_lan) || !read_string(*parsed, "mode", mode) ||
        !read_string(*parsed, "log_level", log_level) || !read_string(*parsed, "baseline", baseline) || !read_uint(*parsed, "mixed_port", port)) return kBadData;
    if (port && *port > 65535) return kBadData;
    if (tun) settings.tun = *tun;
    if (ipv6) settings.ipv6 = *ipv6;
    if (allow_lan) settings.allow_lan = *allow_lan;
    if (mode) settings.mode = *mode;
    if (log_level) settings.log_level = *log_level;
    if (baseline) settings.baseline = *baseline;
    if (port) settings.mixed_port = static_cast<uint16_t>(*port);
    return settings;
}
bool valid_id(std::string_view id) {
    return !id.empty() && id.size() < 96 && std::all_of(id.begin(), id.end(), [](unsigned char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_'; });
}
uint64_t node_count(std::string_view bytes) {
    const auto root = load_yaml(bytes);
    if (!root || !root->IsMap()) return 0;
    const YAML::Node proxies = (*root)["proxies"];
    return proxies.IsDefined() && proxies.IsSequence() ? proxies.size() : 0;
}
Res<std::string> merge(std::string_view bytes, const Settings& settings, const std::string& socket) {
    const auto loaded = load_yaml(bytes);
    if (!loaded) return fail("订阅不是有效 YAML（内容隐藏）");
    YAML::Node value = *loaded;
    const bool has_proxies = value.IsMap() && value["proxies"].IsDefined() && value["proxies"].IsSequence();
    if (!value.IsMap() || (!has_proxies && !is_map(value, "proxy-providers"))) return fail("订阅缺少 proxies / proxy-providers");
    YAML::Node baseline;
    if (const auto parsed = load_yaml(settings.baseline)) baseline = *parsed;
    // Discard every remote control/listener inherited from a subscription; keep outbound definitions and rules.
    for (const char* key : {"external-controller", "external-controller-tls", "external-controller-pipe", "external-ui", "external-ui-url", "external-ui-name", "secret", "listeners",
                            "authentication", "port", "socks-port", "redir-port", "tproxy-port", "ss-config", "vmess-config", "tuic-server", "iptables", "ntp"}) {
        value.remove(key);
    }
    for (const char* key : {"tun", "dns", "sniffer", "profile"}) {
        if (is_map(baseline, key)) value[key] = YAML::Clone(baseline[key]);
        else value.remove(key);
    }
    try {
        if (is_missing(value, "tun")) value["tun"] = YAML::Load("{stack: mixed, auto-route: true, auto-detect-interface: true, strict-route: false, dns-hijack: ['any:53']}");
        if (is_missing(value, "dns")) value["dns"] = YAML::Load("{enable: true, listen: ':53', enhanced-mode: fake-ip, fake-ip-range: 198.18.0.1/16, nameserver: [223.5.5.5, 8.8.8.8]}");
        if (is_missing(value, "sniffer")) value["sniffer"] = YAML::Load("{enable: false}");
        if (is_missing(value, "profile")) value["profile"] = YAML::Load("{}");
        const char* yes = "true";
        const char* no = "false";
        value["tun"]["enable"] = settings.tun ? yes : no;
        value["tun"]["device"] = "mayon-clash";
        value["dns"]["ipv6"] = settings.ipv6 ? yes : no;
        value["profile"]["store-selected"] = yes;
        value["external-controller-unix"] = socket;
        value["mixed-port"] = std::to_string(settings.mixed_port);
        value["allow-lan"] = settings.allow_lan ? yes : no;
        value["bind-address"] = settings.allow_lan ? "*" : "127.0.0.1";
        value["mode"] = settings.mode;
        value["ipv6"] = settings.ipv6 ? yes : no;
        value["log-level"] = settings.log_level;
        value["geodata-mode"] = yes;
        value["geo-auto-update"] = no;
        YAML::Emitter out;
        YamlBudget budget;
        if (!emit_yaml(out, value, budget, 0) || !out.good()) return fail("配置编码失败");
        return std::string(out.c_str()) + "\n";
    } catch (const std::exception&) {
        return fail("配置编码失败");
    }
}
HeaderMeta header_meta(const Headers& headers, const std::string& host) {
    HeaderMeta meta;
    std::string name;
    if (auto title = header_value(headers, "profile-title"); title && visible_ascii(*title)) {
        if (title->rfind("base64:", 0) == 0) {
            bool ok = false;
            std::string decoded = base64_decode(std::string_view(*title).substr(7), ok);
            const std::string round = tui::encode(tui::decode(decoded));
            name = ok && round == decoded ? decoded : "";
        } else {
            name = *title;
        }
    }
    if (tui::trim(name).empty()) {
        name.clear();
        if (const auto disposition = header_value(headers, "content-disposition"); disposition && visible_ascii(*disposition)) {
            std::vector<std::string> fields;
            std::string_view rest = *disposition;
            while (true) {
                const auto semi = rest.find(';');
                fields.push_back(tui::trim(rest.substr(0, semi)));
                if (semi == std::string_view::npos) break;
                rest.remove_prefix(semi + 1);
            }
            for (const std::string& field : fields) {
                if (field.rfind("filename*=", 0) == 0) {
                    std::string_view value = trim_quotes(std::string_view(field).substr(10));
                    if (const auto mark = value.rfind("''"); mark != std::string_view::npos) value.remove_prefix(mark + 2);
                    name = percent_decode(value);
                    break;
                }
            }
            if (name.empty()) {
                for (const std::string& field : fields) {
                    if (field.rfind("filename=", 0) == 0) {
                        name = std::string(trim_quotes(std::string_view(field).substr(9)));
                        break;
                    }
                }
            }
        }
    }
    if (tui::trim(name).empty()) name = host;
    meta.name = safe_name(name);
    for (const auto& [key, value] : headers) {
        constexpr std::string_view suffix = "subscription-userinfo";
        if (key.size() < suffix.size() || key.compare(key.size() - suffix.size(), suffix.size(), suffix) != 0) continue;
        if (key.size() != suffix.size() && key[key.size() - suffix.size() - 1] != '-') continue;
        if (visible_ascii(value)) meta.usage = Usage::from_header(value);
        break;
    }
    if (const auto interval = header_value(headers, "profile-update-interval")) {
        uint64_t parsed = 0;
        const auto [ptr, error] = std::from_chars(interval->data(), interval->data() + interval->size(), parsed);
        if (error == std::errc{} && ptr == interval->data() + interval->size() && !interval->empty()) meta.interval = std::clamp<uint64_t>(parsed, 1, 8760);
    }
    return meta;
}
Res<Download> download(std::string_view raw, std::optional<uint16_t> proxy_port) {
    const auto origin = parse_url(raw);
    if (!origin) return fail("订阅 URL 无效（内容隐藏）");
    const auto attempt = [&](std::optional<uint16_t> port) -> Res<Download> {
        FetchOptions options;
        options.url = origin->text;
        options.redirects = 5;
        options.user_agent = "clash.meta/mayon-clash";
        if (port) options.proxy = "http://127.0.0.1:" + std::to_string(*port);
        Fetched got;
        if (!fetch(options, got)) return fail("订阅下载失败（URL 隐藏）");
        if (got.status >= 400) return fail("订阅服务器返回错误（URL 隐藏）");
        if (got.too_large) return fail("订阅超过 32 MiB");
        const HeaderMeta meta = header_meta(got.headers, origin->host);
        if (got.body.rfind("\xEF\xBB\xBF", 0) == 0) got.body.erase(0, 3);
        return Download{std::move(got.body), meta.name, meta.usage, meta.interval};
    };
    auto first = attempt(std::nullopt);
    if (first || !proxy_port) return first;
    return attempt(proxy_port);
}
Res<Usage> usage_request(std::string_view raw, const std::string& proxy) {
    const auto url = parse_url(raw);
    if (!url) return fail("订阅 URL 无效");
    for (const bool head : {true, false}) {
        FetchOptions options;
        options.url = url->text;
        options.proxy = proxy;
        options.timeout_ms = 15000;
        options.head = head;
        options.stop_after_headers = !head;
        Fetched got;
        if (!fetch(options, got)) return fail("用量请求失败（URL 已隐藏）");
        if (got.status >= 200 && got.status < 300) {
            if (const auto value = header_value(got.headers, "subscription-userinfo")) {
                const auto usage = visible_ascii(*value) ? Usage::from_header(*value) : std::nullopt;
                if (!usage) return fail("用量响应头格式无效");
                return *usage;
            }
        }
    }
    return fail("服务器未返回 subscription-userinfo；未修改本地订阅");
}
bool validation_network_filter() {
    // seccomp_data.nr is at 0; args[0] (socket family) at 16 on Linux.
    // Allow AF_UNIX/AF_NETLINK for local inspection; deny Internet socket creation.
    static sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, 0),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_socket, 0, 4),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, 16),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_INET, 1, 0),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_INET6, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | ENETUNREACH),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    static sock_fprog program = {static_cast<unsigned short>(std::size(filter)), filter};
    return ::prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0 && ::prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) == 0;
}

// ---- Transactions ------------------------------------------------------------------------------
Res<> private_dir(const fs::path& path) {
    std::error_code error;
    fs::create_directories(path, error);
    if (error || ::chmod(path.c_str(), 0700) != 0) return fail("无法创建私有数据目录");
    return {};
}
Res<> replace_file(const fs::path& path, std::string_view bytes) {
    auto temp = stage(path, bytes);
    if (!temp) return std::unexpected(temp.error());
    if (::rename(temp->path.c_str(), path.c_str()) != 0) return fail("原子替换失败");
    temp->path.clear();
    const fs::path parent = path.parent_path();
    if (!parent.empty()) {
        const int fd = ::open(parent.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (fd < 0) return fail("目录同步失败");
        const bool ok = ::fsync(fd) == 0;
        ::close(fd);
        if (!ok) return fail("目录同步失败");
    }
    return {};
}
Lock::~Lock() {
    if (fd_ >= 0) {
        ::flock(fd_, LOCK_UN);
        ::close(fd_);
    }
}
Res<Lock> Native::lock() const {
    // flock serializes the TUI, the CLI, automatic updates and the Rust version sharing this directory.
    if (auto made = private_dir(data); !made) return std::unexpected(made.error());
    if (auto made = private_dir(data / "subscriptions"); !made) return std::unexpected(made.error());
    const int fd = ::open((data / "writer.lock").c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (fd < 0) return fail("无法打开写入锁");
    if (::flock(fd, LOCK_EX | LOCK_NB) != 0) {
        ::close(fd);
        return fail("另一个订阅或设置操作正在进行");
    }
    return Lock(fd);
}
namespace {
// NotFound reads as defaults, other failures are errors, like the Rust version.
std::optional<std::string> read_data(const fs::path& path, bool& error) {
    error = false;
    std::error_code code;
    const auto state = fs::status(path, code);
    if (state.type() == fs::file_type::not_found) return std::nullopt;
    auto text = read_file(path);
    if (!text) error = true;
    return text;
}
}  // namespace
Res<Store> Native::store() const {
    bool error = false;
    const auto text = read_data(data / "subscriptions.toml", error);
    if (error) return fail("无法读取本地数据");
    if (!text) return Store{};
    auto parsed = decode_store(*text);
    if (!parsed) return parsed;
    if (std::any_of(parsed->items.begin(), parsed->items.end(), [](const Subscription& item) { return !valid_id(item.id); })) return fail("订阅索引含无效 ID");
    return parsed;
}
Res<Settings> Native::settings() const {
    bool error = false;
    const auto text = read_data(data / "settings.toml", error);
    if (error) return fail("无法读取本地数据");
    if (!text) return Settings{};
    return decode_settings(*text);
}
Res<Settings> Native::initial_settings() const {
    std::error_code ignored;
    if (fs::exists(data / "settings.toml", ignored)) return settings();
    return Settings{};
}
Res<> Native::seed_geo() const {
    for (const auto& [variable, name] : {std::pair{"MAYON_CLASH_GEOIP", "GeoIP.dat"}, std::pair{"MAYON_CLASH_GEOSITE", "GeoSite.dat"}, std::pair{"MAYON_CLASH_MMDB", "Country.mmdb"}}) {
        const fs::path path = data / name;
        std::error_code ignored;
        if (fs::exists(path, ignored)) continue;
        const char* source = std::getenv(variable);
        if (!source) continue;
        const auto bytes = read_file(source);
        if (!bytes) return fail("无法读取初始 Geo 数据");
        if (auto written = replace_file(path, *bytes); !written) return written;
    }
    return {};
}
Res<> Native::validate(std::string_view bytes) const {
    if (auto seeded = seed_geo(); !seeded) return seeded;
    auto candidate = stage(data / "validation.yaml", bytes);
    if (!candidate) return std::unexpected(candidate.error());
    // Config tests must never fetch subscription, provider or Geo data; only this child loses Internet sockets.
    const Ran ran = run_process({mihomo, "-t", "-d", data.string(), "-f", candidate->path.string()}, false, true, 45000);
    if (!ran.success) return fail("mihomo 配置校验失败或超时；保留原配置（详细内容隐藏）");
    return {};
}
Res<fs::path> Native::profile_path(std::string_view id) const {
    if (!valid_id(id)) return fail("订阅 ID 无效");
    return data / "subscriptions" / (std::string(id) + ".yaml");
}
Res<> Native::reload_checked(const Settings& wanted) const {
    const Client client{socket, nullptr};
    if (!client.reload()) return fail("内核热加载失败");
    const auto actual = client.configs();
    if (!actual) return fail("热加载后无法确认运行状态");
    // ApplyConfig can answer 204 even if a listener failed to bind.
    if (actual->mode != wanted.mode || actual->tun != wanted.tun || actual->mixed_port != std::optional<uint16_t>(wanted.mixed_port)) return fail("热加载后 TUN/监听端口/模式与设置不符");
    return {};
}
Res<> Native::commit(const Store& store, const Settings& wanted, const std::optional<std::pair<std::string, std::string>>& changed, bool running) const {
    std::optional<std::string> config;
    if (store.current) {
        std::string bytes;
        if (changed && changed->first == *store.current) {
            bytes = changed->second;
        } else {
            const auto path = profile_path(*store.current);
            if (!path) return std::unexpected(path.error());
            auto cached = read_file(*path);
            if (!cached) return fail("当前订阅缓存不可读");
            bytes = std::move(*cached);
        }
        auto merged = merge(bytes, wanted, socket);
        if (!merged) return std::unexpected(merged.error());
        config = std::move(*merged);
    }
    if (config) {
        if (auto valid = validate(*config); !valid) return valid;
    }
    const auto store_text = encode_store(store);
    if (!store_text) return std::unexpected(store_text.error());
    const auto settings_text = encode_settings(wanted);
    if (!settings_text) return std::unexpected(settings_text.error());
    std::vector<std::pair<fs::path, std::string>> writes{{data / "subscriptions.toml", *store_text}, {data / "settings.toml", *settings_text}};
    if (changed) {
        const auto path = profile_path(changed->first);
        if (!path) return std::unexpected(path.error());
        writes.emplace_back(*path, changed->second);
    }
    if (config) writes.emplace_back(data / "config.yaml", *config);
    const auto previous_settings = settings();
    if (!previous_settings) return std::unexpected(previous_settings.error());
    std::vector<std::pair<fs::path, std::optional<std::string>>> old;
    for (const auto& [path, bytes] : writes) old.emplace_back(path, read_file(path));
    const auto apply = [&]() -> Res<> {
        if (config) {
            if (const auto previous = read_file(data / "config.yaml")) {
                if (auto saved = replace_file(data / "config.previous.yaml", *previous); !saved) return saved;
            }
        }
        for (const auto& [path, bytes] : writes) {
            if (auto written = replace_file(path, bytes); !written) return written;
        }
        if (running && config) return reload_checked(wanted);
        return {};
    };
    const auto result = apply();
    if (result) return {};
    bool restored = true;
    for (const auto& [path, bytes] : old) {
        if (bytes) {
            restored = replace_file(path, *bytes).has_value() && restored;
        } else {
            std::error_code code;
            if (fs::exists(path, code)) {
                fs::remove(path, code);
                restored = !code && restored;
            }
        }
    }
    if (running) restored = reload_checked(*previous_settings).has_value() && restored;
    return fail(result.error() + (restored ? "；已回滚文件和运行配置" : "；回滚未完成，请 X 关闭服务后检查数据目录"));
}
Res<> Native::add(std::string_view raw, std::string_view name, bool running) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    const auto wanted = initial_settings();
    if (!wanted) return std::unexpected(wanted.error());
    auto index = store();
    if (!index) return std::unexpected(index.error());
    auto got = download(raw, running ? std::optional<uint16_t>(wanted->mixed_port) : std::nullopt);
    if (!got) return std::unexpected(got.error());
    const auto merged = merge(got->bytes, *wanted, socket);
    if (!merged) return std::unexpected(merged.error());
    if (auto valid = validate(*merged); !valid) return valid;
    const std::string id = "s" + std::to_string(now_nanos());
    const auto url = parse_url(raw);
    if (!url) return fail("订阅 URL 无效（内容隐藏）");
    const bool unnamed = unicode_words(name).empty();
    index->items.push_back({id, unnamed ? got->name : safe_name(name), url->text, unix_now(), got->interval, got->usage, node_count(got->bytes), false});
    if (!index->current) index->current = id;
    return commit(*index, *wanted, std::pair{id, got->bytes}, running);
}
Res<> Native::update(std::string_view id, bool running, const std::optional<std::string>& new_url) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    auto index = store();
    if (!index) return std::unexpected(index.error());
    const auto wanted = initial_settings();
    if (!wanted) return std::unexpected(wanted.error());
    const auto item = std::find_if(index->items.begin(), index->items.end(), [&](const Subscription& row) { return row.id == id; });
    if (item == index->items.end()) return fail("订阅不存在");
    const std::string raw = new_url.value_or(item->url);
    auto got = download(raw, running ? std::optional<uint16_t>(wanted->mixed_port) : std::nullopt);
    if (!got) return std::unexpected(got.error());
    const auto merged = merge(got->bytes, *wanted, socket);
    if (!merged) return std::unexpected(merged.error());
    if (auto valid = validate(*merged); !valid) return valid;
    const auto url = parse_url(raw);
    if (!url) return fail("订阅 URL 无效（内容隐藏）");
    item->url = url->text;
    item->updated = unix_now();
    item->usage = got->usage;
    item->interval_hours = got->interval;
    item->nodes = node_count(got->bytes);
    return commit(*index, *wanted, std::pair{std::string(id), got->bytes}, running);
}
Res<> Native::select(std::string_view id, bool running) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    auto index = store();
    if (!index) return std::unexpected(index.error());
    if (std::none_of(index->items.begin(), index->items.end(), [&](const Subscription& row) { return row.id == id; })) return fail("订阅不存在");
    index->current = std::string(id);
    const auto wanted = initial_settings();
    if (!wanted) return std::unexpected(wanted.error());
    return commit(*index, *wanted, std::nullopt, running);
}
Res<> Native::rename(std::string_view id, std::string_view name) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    auto index = store();
    if (!index) return std::unexpected(index.error());
    if (unicode_words(name).empty()) return fail("名称不能为空");
    const auto item = std::find_if(index->items.begin(), index->items.end(), [&](const Subscription& row) { return row.id == id; });
    if (item == index->items.end()) return fail("订阅不存在");
    item->name = safe_name(name);
    const auto text = encode_store(*index);
    if (!text) return std::unexpected(text.error());
    return replace_file(data / "subscriptions.toml", *text);
}
Res<> Native::remove(std::string_view id) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    auto index = store();
    if (!index) return std::unexpected(index.error());
    if (index->current && *index->current == id) return fail("当前订阅不能删除；请先切换");
    if (std::none_of(index->items.begin(), index->items.end(), [&](const Subscription& row) { return row.id == id; })) return fail("订阅不存在");
    std::erase_if(index->items, [&](const Subscription& row) { return row.id == id; });
    const auto text = encode_store(*index);
    if (!text) return std::unexpected(text.error());
    if (auto written = replace_file(data / "subscriptions.toml", *text); !written) return written;
    const auto path = profile_path(id);
    if (!path) return std::unexpected(path.error());
    std::error_code code;
    if (!fs::remove(*path, code) || code) return fail("索引已删除；缓存文件删除失败");
    return {};
}
Res<> Native::change(std::string_view key, std::string_view value, bool running) const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    auto wanted = initial_settings();
    if (!wanted) return std::unexpected(wanted.error());
    if (auto set = wanted->set(key, value); !set) return set;
    const auto index = store();
    if (!index) return std::unexpected(index.error());
    return commit(*index, *wanted, std::nullopt, running);
}
Res<> Native::generate() const {
    const auto guard = lock();
    if (!guard) return std::unexpected(guard.error());
    const auto index = store();
    if (!index) return std::unexpected(index.error());
    if (!index->current) return fail("尚无订阅；请到 3 订阅添加");
    const auto wanted = initial_settings();
    if (!wanted) return std::unexpected(wanted.error());
    return commit(*index, *wanted, std::nullopt, false);
}
Res<> Native::service(std::string_view verb) const {
    if (verb != "start" && verb != "stop" && verb != "restart") return fail("服务操作无效");
    const Ran ran = run_process({systemctl, "--no-ask-password", std::string(verb), kService}, false, false, 40000);
    if (ran.success) return {};
    return fail(failure());
}
std::string Native::failure() const {
    const Ran show = run_process({systemctl, "show", kService, "-p", "Result,ExecMainStatus"}, true, false, 10000);
    const Ran journal = run_process({journalctl, "-u", kService, "-n", "20", "--no-pager", "-o", "cat"}, true, false, 10000);
    // Classify locally; the raw journal may hold node names and credentials, so it is never rendered.
    const std::string& logs = journal.output;
    std::string reason = "服务启动失败，请检查单元状态；日志内容已隐藏";
    if (logs.find("校验") != std::string::npos || logs.find("config") != std::string::npos) reason = "配置缺失或校验失败，请重新选择/更新订阅";
    else if (logs.find("permission") != std::string::npos || logs.find("Operation not permitted") != std::string::npos) reason = "权限不足，请检查服务 capability 与 polkit";
    std::string fields;
    std::istringstream lines(show.output);
    for (std::string line; std::getline(lines, line);) {
        if (line.rfind("Result=", 0) != 0 && line.rfind("ExecMainStatus=", 0) != 0) continue;
        if (!std::all_of(line.begin(), line.end(), [](unsigned char c) { return std::isalnum(c) || c == '=' || c == '-' || c == '_'; })) continue;
        if (!fields.empty()) fields += " ";
        fields += line;
    }
    return reason + " · " + fields;
}
}  // namespace clash
