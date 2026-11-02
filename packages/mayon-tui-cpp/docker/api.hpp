// Docker Engine v1.47 models and blocking requests. Private to this tool. Workers only.
#pragma once
#include <cstdint>
#include <functional>
#include <map>
#include <nlohmann/json.hpp>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "ui/http.hpp"

namespace dock {
using json = nlohmann::json;
inline constexpr const char* kComposeProject = "com.docker.compose.project";

struct Port {
    std::optional<std::string> ip;
    uint16_t private_port = 0;
    std::optional<uint16_t> public_port;
    std::string kind;
};
struct Container {
    std::string id;
    std::vector<std::string> names;
    std::string image, state, status;
    std::vector<Port> ports;
    std::map<std::string, std::string> labels;
    const std::string* project() const;
};
struct Image {
    std::string id;
    std::vector<std::string> tags;
    uint64_t size = 0;
};
struct UsageData {
    int64_t size = -1;
    int64_t refs = -1;
};
struct Volume {
    std::string name;
    std::optional<UsageData> usage;
};
struct ImageDisk {
    std::string id;
    int64_t containers = -1;
    uint64_t size = 0;
    int64_t shared = -1;
    std::vector<std::string> tags;
};
struct BuildDisk {
    std::string id, description;
    uint64_t size = 0;
    bool in_use = true;  // Absent means protected.
    bool is_shared = true;
};
struct Disk {
    std::vector<ImageDisk> images;
    std::vector<json> containers;
    std::vector<Volume> volumes;
    std::vector<BuildDisk> build_cache;
    uint64_t layers_size = 0;
};
struct Info {
    std::string version;
};
struct StatView {
    double cpu = 0;
    uint64_t memory = 0;
    uint64_t limit = 0;
};
// Decoders are as strict as the serde models: a wrong type or missing required field throws.
Container decode_container(const json& value);
Image decode_image(const json& value);
Volume decode_volume(const json& value);
std::vector<Volume> decode_volumes(const json& value);
Disk decode_disk(const json& value);
StatView decode_stats(const json& value);

bool is_dangling(const std::vector<std::string>& tags);
bool is_default_docker_socket(std::string_view host, const char* runtime_dir);
void merge_volume_usage(std::vector<Volume>& volumes, const Disk& disk);
// Throws when the ID cannot be anchored exactly; there is never an unfiltered prune.
std::string cache_prune_path(const std::string& id);
std::string enc(std::string_view text);
std::vector<std::string> drain_raw_log_lines(std::string& buffer);
std::vector<std::string> drain_log_frames(std::string& buffer);
bool cap_log_buffer(std::string& buffer, size_t max_bytes);
// Removes control characters but keeps '<', since tags such as <none> and log text are not markup.
std::string safe(std::string_view text);
bool valid_utf8(std::string_view text);
// Like str::lines: splits on \n, strips one trailing \r, no final empty line.
std::vector<std::string> split_lines(std::string_view text);
std::string status_text(long status);

// All requests throw std::runtime_error carrying the message shown to the user.
struct Engine {
    std::string host;
    std::string socket;
    bool can_stop_local_daemon = false;
    tui::Cancel cancel;
    static Engine create(std::optional<std::string> host);
    Engine with(tui::Cancel token) const;
    void ping() const;
    std::vector<Container> containers() const;
    std::vector<Image> images() const;
    std::vector<Volume> volumes() const;
    Info info() const;
    Disk disk() const;
    StatView stats(const std::string& id) const;
    bool inspect_tty(const std::string& id) const;
    // Blocks until the stream ends; `on_data` returns false to stop. Returns the HTTP status.
    long logs(const std::string& id, size_t tail, std::function<bool(std::string_view)> on_data) const;
    void start(const std::string& id) const;
    void stop(const std::string& id) const;
    void restart(const std::string& id) const;
    void remove_container(const std::string& id) const;
    void remove_image(const std::string& id) const;
    void remove_volume(const std::string& name) const;
    json remove_cache(const std::string& id) const;
    bool exec_has_bash(const std::string& id) const;

private:
    tui::HttpReply request(const std::string& method, const std::string& path, std::string body = {}, long timeout_ms = 10000) const;
    json get_json(const std::string& path) const;
    void action(const std::string& method, const std::string& path) const;
};
}  // namespace dock
