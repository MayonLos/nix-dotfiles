#include "api.hpp"

#include <algorithm>
#include <cstdlib>
#include <format>
#include <limits>

#include "ui/text.hpp"

namespace dock {
namespace {
using Fail = std::runtime_error;
const char* const kOffline = "Docker 启动中…";
const char* const kBadJson = "Docker API 响应无法解析";
const json* field(const json& object, const char* name) {
    if (!object.is_object()) throw Fail(kBadJson);
    const auto it = object.find(name);
    return it == object.end() ? nullptr : &*it;
}
std::string as_string(const json& value) {
    if (!value.is_string()) throw Fail(kBadJson);
    return value.get<std::string>();
}
uint64_t as_u64(const json& value) {
    // serde's u64 accepts any non-negative JSON integer, signed or unsigned in the DOM.
    if (value.is_number_unsigned()) return value.get<uint64_t>();
    if (value.is_number_integer()) {
        const auto raw = value.get<int64_t>();
        if (raw < 0) throw Fail(kBadJson);
        return static_cast<uint64_t>(raw);
    }
    throw Fail(kBadJson);
}
int64_t as_i64(const json& value) {
    if (value.is_number_unsigned()) {
        const auto raw = value.get<uint64_t>();
        if (raw > static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) throw Fail(kBadJson);
        return static_cast<int64_t>(raw);
    }
    if (!value.is_number_integer()) throw Fail(kBadJson);
    return value.get<int64_t>();
}
uint16_t as_u16(const json& value) {
    const uint64_t raw = as_u64(value);
    if (raw > 65535) throw Fail(kBadJson);
    return static_cast<uint16_t>(raw);
}
std::string text_or(const json& object, const char* name) {
    const json* value = field(object, name);
    return value ? as_string(*value) : std::string();
}
std::string required_text(const json& object, const char* name) {
    const json* value = field(object, name);
    if (!value) throw Fail(kBadJson);
    return as_string(*value);
}
uint64_t u64_or(const json& object, const char* name) {
    const json* value = field(object, name);
    return value ? as_u64(*value) : 0;
}
int64_t i64_or(const json& object, const char* name, int64_t fallback) {
    const json* value = field(object, name);
    return value ? as_i64(*value) : fallback;
}
bool bool_or(const json& object, const char* name, bool fallback) {
    const json* value = field(object, name);
    if (!value) return fallback;
    if (!value->is_boolean()) throw Fail(kBadJson);
    return value->get<bool>();
}
// Docker answers null for empty collections.
const json* list_field(const json& object, const char* name) {
    const json* value = field(object, name);
    if (!value || value->is_null()) return nullptr;
    if (!value->is_array()) throw Fail(kBadJson);
    return value;
}
std::vector<std::string> strings(const json& object, const char* name) {
    std::vector<std::string> out;
    if (const json* list = list_field(object, name)) {
        for (const json& item : *list) out.push_back(as_string(item));
    }
    return out;
}
std::optional<UsageData> decode_usage(const json& object) {
    const json* usage = field(object, "UsageData");
    if (!usage || usage->is_null()) return std::nullopt;
    return UsageData{i64_or(*usage, "Size", -1), i64_or(*usage, "RefCount", -1)};
}
uint64_t saturating_sub(uint64_t a, uint64_t b) { return a > b ? a - b : 0; }
const json& object_or_empty(const json& object, const char* name) {
    static const json empty = json::object();
    const json* value = field(object, name);
    return value ? *value : empty;
}
std::string docker_error(const tui::HttpReply& reply) {
    std::string message = "请求失败";
    const json body = json::parse(reply.body, nullptr, false);
    if (body.is_object() && body.contains("message") && body["message"].is_string()) message = body["message"].get<std::string>();
    return "Docker API " + status_text(reply.status) + ": " + message;
}
bool success(long status) { return status >= 200 && status < 300; }
}  // namespace

const std::string* Container::project() const {
    const auto it = labels.find(kComposeProject);
    return it == labels.end() ? nullptr : &it->second;
}
Container decode_container(const json& value) {
    Container out;
    out.id = required_text(value, "Id");
    out.names = strings(value, "Names");
    out.image = text_or(value, "Image");
    out.state = text_or(value, "State");
    out.status = text_or(value, "Status");
    if (const json* list = list_field(value, "Ports")) {
        for (const json& item : *list) {
            Port port;
            const json* ip = field(item, "IP");
            if (ip && !ip->is_null()) port.ip = as_string(*ip);
            const json* inner = field(item, "PrivatePort");
            if (!inner) throw Fail(kBadJson);
            port.private_port = as_u16(*inner);
            const json* outer = field(item, "PublicPort");
            if (outer && !outer->is_null()) port.public_port = as_u16(*outer);
            port.kind = required_text(item, "Type");
            out.ports.push_back(std::move(port));
        }
    }
    if (const json* labels = field(value, "Labels"); labels && !labels->is_null()) {
        if (!labels->is_object()) throw Fail(kBadJson);
        for (const auto& [key, item] : labels->items()) out.labels[key] = as_string(item);
    }
    return out;
}
Image decode_image(const json& value) { return Image{required_text(value, "Id"), strings(value, "RepoTags"), u64_or(value, "Size")}; }
Volume decode_volume(const json& value) { return Volume{required_text(value, "Name"), decode_usage(value)}; }
std::vector<Volume> decode_volumes(const json& value) {
    std::vector<Volume> out;
    if (const json* list = list_field(value, "Volumes")) {
        for (const json& item : *list) out.push_back(decode_volume(item));
    }
    return out;
}
Disk decode_disk(const json& value) {
    Disk disk;
    if (const json* list = list_field(value, "Images")) {
        for (const json& item : *list) disk.images.push_back(ImageDisk{text_or(item, "Id"), i64_or(item, "Containers", -1), u64_or(item, "Size"), i64_or(item, "SharedSize", -1), strings(item, "RepoTags")});
    }
    if (const json* list = list_field(value, "Containers")) disk.containers.assign(list->begin(), list->end());
    disk.volumes = decode_volumes(value);
    if (const json* list = list_field(value, "BuildCache")) {
        for (const json& item : *list) disk.build_cache.push_back(BuildDisk{text_or(item, "ID"), text_or(item, "Description"), u64_or(item, "Size"), bool_or(item, "InUse", true), bool_or(item, "Shared", true)});
    }
    disk.layers_size = u64_or(value, "LayersSize");
    return disk;
}
StatView decode_stats(const json& value) {
    for (const char* required : {"cpu_stats", "precpu_stats", "memory_stats"}) {
        if (!field(value, required)) throw Fail(kBadJson);
    }
    const json& cpu = value["cpu_stats"];
    const json& pre = value["precpu_stats"];
    const json& memory = value["memory_stats"];
    const auto total = [](const json& stats) { return u64_or(object_or_empty(stats, "cpu_usage"), "total_usage"); };
    const auto c = static_cast<double>(saturating_sub(total(cpu), total(pre)));
    const auto s = static_cast<double>(saturating_sub(u64_or(cpu, "system_cpu_usage"), u64_or(pre, "system_cpu_usage")));
    const uint64_t online = u64_or(cpu, "online_cpus");
    const uint64_t n = online > 0 ? online : 1;
    u64_or(pre, "online_cpus");  // Same type check as the other sample.
    const json& stats = object_or_empty(memory, "stats");
    if (!stats.is_object()) throw Fail(kBadJson);
    for (const auto& [key, item] : stats.items()) as_u64(item);
    uint64_t cache = 0;
    if (stats.contains("inactive_file")) cache = as_u64(stats["inactive_file"]);
    else if (stats.contains("cache")) cache = as_u64(stats["cache"]);
    return StatView{s > 0. ? c / s * 100. * static_cast<double>(n) : 0., saturating_sub(u64_or(memory, "usage"), cache), u64_or(memory, "limit")};
}
bool is_dangling(const std::vector<std::string>& tags) {
    return std::all_of(tags.begin(), tags.end(), [](const std::string& tag) { return tag.starts_with("<none>"); });
}
bool is_default_docker_socket(std::string_view host, const char* runtime_dir) { return runtime_dir && host == "unix://" + std::string(runtime_dir) + "/docker.sock"; }
void merge_volume_usage(std::vector<Volume>& volumes, const Disk& disk) {
    for (Volume& volume : volumes) {
        if (volume.usage) continue;
        const auto it = std::find_if(disk.volumes.begin(), disk.volumes.end(), [&](const Volume& entry) { return entry.name == volume.name; });
        if (it != disk.volumes.end()) volume.usage = it->usage;
    }
}
std::string enc(std::string_view text) {
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string out;
    for (const char raw : text) {
        const auto c = static_cast<unsigned char>(raw);
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.') {
            out += raw;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}
std::string cache_prune_path(const std::string& id) {
    const bool exact = !id.empty() && std::all_of(id.begin(), id.end(), [](char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'; });
    if (!exact) throw Fail("缓存 ID 不支持精确清理；未执行");
    // BuildKit treats the id filter as a regex, so a strictly validated ID is anchored.
    return "/build/prune?all=true&filters=" + enc(R"({"id":["^)" + id + R"($"],"inuse":["false"],"shared":["false"]})");
}
bool valid_utf8(std::string_view text) {
    for (size_t i = 0; i < text.size();) {
        const auto lead = static_cast<unsigned char>(text[i]);
        const size_t length = lead < 0x80 ? 1 : (lead >> 5) == 6 ? 2 : (lead >> 4) == 14 ? 3 : (lead >> 3) == 30 ? 4 : 0;
        if (length == 0 || i + length > text.size()) return false;
        uint32_t value = length == 1 ? lead : lead & (0xFFu >> (length + 1));
        for (size_t k = 1; k < length; ++k) {
            const auto next = static_cast<unsigned char>(text[i + k]);
            if ((next & 0xC0) != 0x80) return false;
            value = (value << 6) | (next & 0x3F);
        }
        constexpr uint32_t minimum[5] = {0, 0, 0x80, 0x800, 0x10000};
        if (value < minimum[length] || value > 0x10FFFF || (value >= 0xD800 && value < 0xE000)) return false;
        i += length;
    }
    return true;
}
std::vector<std::string> drain_raw_log_lines(std::string& buffer) {
    std::vector<std::string> out;
    size_t from = 0;
    for (size_t end = 0; (end = buffer.find('\n', from)) != std::string::npos; from = end + 1) {
        std::string line = tui::encode(tui::decode(std::string_view(buffer).substr(from, end - from)));
        while (line.ends_with('\r')) line.pop_back();
        out.push_back(std::move(line));
    }
    buffer.erase(0, from);
    return out;
}
// Docker multiplexed stream frames: [stream, 0,0,0, big-endian length, payload].
std::vector<std::string> drain_log_frames(std::string& buffer) {
    std::vector<std::string> out;
    size_t consumed = 0;
    while (buffer.size() - consumed >= 8) {
        const char* frame = buffer.data() + consumed;
        if (frame[1] != 0 || frame[2] != 0 || frame[3] != 0) break;
        const auto byte = [&](int i) { return static_cast<size_t>(static_cast<unsigned char>(frame[i])); };
        const size_t n = byte(4) << 24 | byte(5) << 16 | byte(6) << 8 | byte(7);
        if (buffer.size() - consumed < 8 + n) break;
        const std::string_view payload(frame + 8, n);
        if (valid_utf8(payload)) {
            std::string line(payload);
            while (line.ends_with('\r') || line.ends_with('\n')) line.pop_back();
            out.push_back(std::move(line));
        }
        consumed += 8 + n;
    }
    buffer.erase(0, consumed);
    return out;
}
bool cap_log_buffer(std::string& buffer, size_t max_bytes) {
    if (buffer.size() <= max_bytes) return false;
    buffer.clear();
    return true;
}
std::string safe(std::string_view text) {
    std::u32string kept;
    for (const char32_t ch : tui::decode(text)) {
        if (ch == U'\n' || (ch >= 0x20 && ch != 0x7F && !(ch >= 0x80 && ch < 0xA0))) kept.push_back(ch);
    }
    return tui::encode(kept);
}
std::vector<std::string> split_lines(std::string_view text) {
    std::vector<std::string> out;
    while (!text.empty()) {
        const size_t end = text.find('\n');
        std::string_view line = text.substr(0, end);
        if (end != std::string_view::npos && line.ends_with('\r')) line.remove_suffix(1);
        out.emplace_back(line);
        if (end == std::string_view::npos) break;
        text.remove_prefix(end + 1);
    }
    return out;
}
std::string status_text(long status) {
    static const std::map<long, const char*> names{
        {200, "OK"},
        {201, "Created"},
        {204, "No Content"},
        {304, "Not Modified"},
        {400, "Bad Request"},
        {401, "Unauthorized"},
        {403, "Forbidden"},
        {404, "Not Found"},
        {405, "Method Not Allowed"},
        {406, "Not Acceptable"},
        {408, "Request Timeout"},
        {409, "Conflict"},
        {410, "Gone"},
        {413, "Payload Too Large"},
        {415, "Unsupported Media Type"},
        {422, "Unprocessable Entity"},
        {429, "Too Many Requests"},
        {500, "Internal Server Error"},
        {501, "Not Implemented"},
        {502, "Bad Gateway"},
        {503, "Service Unavailable"},
        {504, "Gateway Timeout"},
    };
    const auto it = names.find(status);
    return std::format("{} {}", status, it == names.end() ? "<unknown status code>" : it->second);
}

Engine Engine::create(std::optional<std::string> requested) {
    const char* runtime_dir = std::getenv("XDG_RUNTIME_DIR");
    std::string host = requested && !requested->empty() ? *requested : runtime_dir ? "unix://" + std::string(runtime_dir) + "/docker.sock" : "";
    if (host.empty()) throw Fail("XDG_RUNTIME_DIR 或 DOCKER_HOST 必须设置");
    if (!host.starts_with("unix://")) throw Fail("DOCKER_HOST 仅支持 unix://；不会回退到其它 daemon");
    std::string_view path = host;
    while (path.starts_with("unix://")) path.remove_prefix(7);
    Engine engine;
    engine.socket = path;
    engine.can_stop_local_daemon = is_default_docker_socket(host, runtime_dir);
    engine.host = std::move(host);
    return engine;
}
Engine Engine::with(tui::Cancel token) const {
    Engine copy = *this;
    copy.cancel = std::move(token);
    return copy;
}
tui::HttpReply Engine::request(const std::string& method, const std::string& path, std::string body, long timeout_ms) const {
    tui::HttpRequest http;
    http.socket = socket;
    http.method = method;
    http.path = "/v1.47" + path;
    http.body = std::move(body);
    http.timeout_ms = timeout_ms;
    http.cancel = cancel;
    tui::HttpReply reply;
    try {
        reply = tui::unix_http(http);
    } catch (const std::exception&) {
        throw Fail(kOffline);
    }
    if (reply.status == 0) throw Fail(kOffline);
    return reply;
}
json Engine::get_json(const std::string& path) const {
    const tui::HttpReply reply = request("GET", path);
    if (!success(reply.status)) throw Fail(docker_error(reply));
    json value = json::parse(reply.body, nullptr, false);
    if (value.is_discarded()) throw Fail(kBadJson);
    return value;
}
void Engine::action(const std::string& method, const std::string& path) const {
    const tui::HttpReply reply = request(method, path);
    if (!success(reply.status) && reply.status != 304) throw Fail(docker_error(reply));
}
void Engine::ping() const {
    if (!success(request("GET", "/_ping").status)) throw Fail(kOffline);
}
std::vector<Container> Engine::containers() const {
    const json value = get_json("/containers/json?all=1");
    std::vector<Container> out;
    if (value.is_null()) return out;
    if (!value.is_array()) throw Fail(kBadJson);
    for (const json& item : value) out.push_back(decode_container(item));
    return out;
}
std::vector<Image> Engine::images() const {
    const json value = get_json("/images/json?all=1");
    std::vector<Image> out;
    if (value.is_null()) return out;
    if (!value.is_array()) throw Fail(kBadJson);
    for (const json& item : value) out.push_back(decode_image(item));
    return out;
}
std::vector<Volume> Engine::volumes() const { return decode_volumes(get_json("/volumes")); }
Info Engine::info() const { return Info{text_or(get_json("/info"), "ServerVersion")}; }
Disk Engine::disk() const { return decode_disk(get_json("/system/df")); }
StatView Engine::stats(const std::string& id) const { return decode_stats(get_json("/containers/" + enc(id) + "/stats?stream=false")); }
bool Engine::inspect_tty(const std::string& id) const {
    const json value = get_json("/containers/" + enc(id) + "/json");
    const json* config = field(value, "Config");
    return config && !config->is_null() && bool_or(*config, "Tty", false);
}
long Engine::logs(const std::string& id, size_t tail, std::function<bool(std::string_view)> on_data) const {
    tui::HttpRequest http;
    http.socket = socket;
    http.path = std::format("/v1.47/containers/{}/logs?follow=1&stdout=1&stderr=1&timestamps=1&tail={}", enc(id), tail);
    http.timeout_ms = 0;
    http.cancel = cancel;
    http.on_data = std::move(on_data);
    return tui::unix_http(http).status;
}
void Engine::start(const std::string& id) const { action("POST", "/containers/" + enc(id) + "/start"); }
void Engine::stop(const std::string& id) const { action("POST", "/containers/" + enc(id) + "/stop?t=10"); }
void Engine::restart(const std::string& id) const { action("POST", "/containers/" + enc(id) + "/restart?t=10"); }
void Engine::remove_container(const std::string& id) const { action("DELETE", "/containers/" + enc(id) + "?force=false&v=false"); }
void Engine::remove_image(const std::string& id) const { action("DELETE", "/images/" + enc(id) + "?force=false&noprune=true"); }
void Engine::remove_volume(const std::string& name) const { action("DELETE", "/volumes/" + enc(name)); }
json Engine::remove_cache(const std::string& id) const {
    const tui::HttpReply reply = request("POST", cache_prune_path(id));
    if (!success(reply.status)) throw Fail(docker_error(reply));
    json value = json::parse(reply.body, nullptr, false);
    if (value.is_discarded()) throw Fail(kBadJson);
    return value;
}
bool Engine::exec_has_bash(const std::string& id) const {
    try {
        const tui::HttpReply created = request("POST", "/containers/" + enc(id) + "/exec", R"({"AttachStdout":false,"AttachStderr":false,"Cmd":["/bin/bash","-lc","exit 0"]})", 30000);
        const json body = json::parse(created.body, nullptr, false);
        if (!body.is_object() || !body.contains("Id") || !body["Id"].is_string()) return false;
        return success(request("POST", "/exec/" + enc(body["Id"].get<std::string>()) + "/start", R"({"Detach":true,"Tty":false})", 30000).status);
    } catch (const std::exception&) {
        return false;
    }
}
}  // namespace dock
