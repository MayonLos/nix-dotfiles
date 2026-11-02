// Controller data, subscription usage, URL handling and small formatters. No I/O here.
#pragma once
#include <chrono>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace clash {
// Safe error categories: bodies and URLs never appear, so they cannot reveal subscription data.
enum class ApiError { Transport, InvalidResponse, Rejected, InvalidEndpoint };
const char* message(ApiError error);

struct DelaySample {
    std::string time;
    uint64_t delay = 0;
    bool operator==(const DelaySample&) const = default;
};
struct Proxy {
    std::string name;
    std::string kind;
    std::optional<std::string> now;
    std::vector<std::string> all;
    std::vector<DelaySample> history;
    bool operator==(const Proxy&) const = default;
};
struct RuntimeConfig {
    std::string mode;
    bool tun = false;
    std::optional<uint16_t> mixed_port;
    bool operator==(const RuntimeConfig&) const = default;
};
struct ConnectionMetadata {
    std::string network, host, destination_ip, destination_port, source_ip, source_port, process, process_path;
    bool operator==(const ConnectionMetadata&) const = default;
};
struct Connection {
    std::string id;
    ConnectionMetadata metadata;
    std::string rule, rule_payload;
    std::vector<std::string> chains;
    uint64_t upload = 0, download = 0;
    std::string start;
    bool operator==(const Connection&) const = default;
};
struct ConnectionsResponse {
    std::vector<Connection> connections;
    uint64_t upload_total = 0, download_total = 0, memory = 0;
};
struct Provider {
    std::string vehicle_type, kind;
    std::vector<Proxy> proxies;
    std::string updated_at;
    uint64_t rule_count = 0;
    bool operator==(const Provider&) const = default;
};
struct RuleExtra {
    uint64_t hit_count = 0;
    std::string hit_at;
    bool operator==(const RuleExtra&) const = default;
};
struct Rule {
    std::string kind, payload, proxy;
    std::optional<RuleExtra> extra;
    bool operator==(const Rule&) const = default;
};
struct LogEntry {
    uint64_t id = 0;
    std::string level, payload;
};
struct Traffic {
    uint64_t up = 0, down = 0, up_total = 0, down_total = 0;
    bool operator==(const Traffic&) const = default;
};
using Proxies = std::map<std::string, Proxy>;
using Providers = std::map<std::string, Provider>;

// All of these throw on malformed input; callers map that to ApiError::InvalidResponse.
Proxies parse_proxies(std::string_view body);
RuntimeConfig parse_config(std::string_view body);
std::string parse_version(std::string_view body);
ConnectionsResponse parse_connections(std::string_view body);
Providers parse_providers(std::string_view body);
std::vector<Rule> parse_rules(std::string_view body);
std::map<std::string, uint64_t> parse_group_delay(std::string_view body);
uint64_t parse_delay(std::string_view body);
LogEntry parse_log(std::string_view body);
Traffic parse_traffic(std::string_view body);

struct Usage {
    uint64_t upload = 0, download = 0, total = 0, expire = 0;
    bool operator==(const Usage&) const = default;
    uint64_t used_bytes() const;
    std::optional<uint64_t> remaining_bytes() const;
    std::optional<double> progress() const;
    // Unix seconds; zero or out of range means no expiry.
    std::optional<int64_t> expires_at() const;
    // Parses `upload=...; download=...; total=...; expire=...`; unknown keys are ignored.
    static std::optional<Usage> from_header(std::string_view header);
};

// A parsed http(s) URL in normalized form, equivalent to what the Rust version stores.
struct Url {
    std::string scheme, host, text;
};
std::optional<Url> parse_url(std::string_view raw);
// Scheme and host only, so credentials and tokens stay hidden.
std::string redact_url(std::string_view raw);

// Encodes one path segment, as the controller routes expect.
std::string encode_segment(std::string_view segment);
std::string encode_path(const std::vector<std::string>& segments);
// application/x-www-form-urlencoded value.
std::string encode_query(std::string_view value);

std::string redact_log(std::string_view text);
bool is_control(char32_t ch);
bool is_space(char32_t ch);
std::vector<std::string> unicode_words(std::string_view text);
std::string safe_name(std::string_view raw);
std::string strip_controls(std::string_view text);

std::string bytes_text(uint64_t value);
// Whole seconds since an RFC 3339 timestamp, nothing when it does not parse.
std::optional<int64_t> rfc3339_seconds(std::string_view text);
std::string age_text(std::string_view start);
std::string local_time(int64_t epoch, const char* format);
int64_t unix_now();
std::string base64_decode(std::string_view text, bool& ok);
}  // namespace clash
