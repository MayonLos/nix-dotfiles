// User-owned subscriptions and config transactions. Upstream errors and bodies never reach diagnostics.
// The files are shared with the Rust version: same paths, formats, modes and writer lock.
#pragma once
#include <expected>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "model.hpp"

namespace clash {
template <class T = void>
using Res = std::expected<T, std::string>;
inline constexpr const char* kService = "mayon-clash.service";

struct Settings {
    bool tun = true;
    std::string mode = "rule";
    bool ipv6 = true;
    bool allow_lan = false;
    std::string log_level = "info";
    uint16_t mixed_port = 7897;
    // Saved base settings; built-in defaults fill this field when it is absent.
    std::string baseline = "tun: {stack: mixed, auto-route: true, auto-detect-interface: true, strict-route: false, dns-hijack: ['any:53']}\ndns: {enable: true, listen: ':53', enhanced-mode: fake-ip, fake-ip-range: 198.18.0.1/16, nameserver: [223.5.5.5, 8.8.8.8]}\nsniffer: {enable: false}\nprofile: {}";
    Res<> set(std::string_view key, std::string_view value);
};
struct Subscription {
    std::string id, name;
    std::string url;  // Sensitive: never print it.
    int64_t updated = 0;
    uint64_t interval_hours = 0;
    std::optional<Usage> usage;
    uint64_t nodes = 0;
    // Retired key, kept round-trippable so ordinary edits do not change the on-disk schema.
    bool legacy_current_marker = false;
};
struct Store {
    std::optional<std::string> current;
    std::vector<Subscription> items;
    std::vector<std::string> due() const;
};

// Text forms of the two index files, identical in schema to the Rust version.
Res<std::string> encode_store(const Store& store);
Res<std::string> encode_settings(const Settings& settings);
Res<Store> decode_store(std::string_view text);
Res<Settings> decode_settings(std::string_view text);

// Applies the local settings onto a subscription body and drops every remote control or listener.
Res<std::string> merge(std::string_view bytes, const Settings& settings, const std::string& socket);
uint64_t node_count(std::string_view bytes);
bool valid_id(std::string_view id);

using Headers = std::vector<std::pair<std::string, std::string>>;  // Names in lower case, first one wins.
struct HeaderMeta {
    std::string name;
    std::optional<Usage> usage;
    uint64_t interval = 24;
};
HeaderMeta header_meta(const Headers& headers, const std::string& host);
struct Download {
    std::string bytes, name;
    std::optional<Usage> usage;
    uint64_t interval = 24;
};
Res<Download> download(std::string_view raw, std::optional<uint16_t> proxy_port);
// HEAD first, then GET without reading the body. Redirects are refused so credentials cannot travel to
// another host, and the explicit proxy is used even for loopback addresses.
Res<Usage> usage_request(std::string_view url, const std::string& proxy);

// Installs the seccomp filter that stops the validator opening Internet sockets. Safe after fork.
bool validation_network_filter();

class Lock {
public:
    explicit Lock(int fd) : fd_(fd) {}
    Lock(Lock&& other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
    Lock(const Lock&) = delete;
    Lock& operator=(const Lock&) = delete;
    Lock& operator=(Lock&&) = delete;
    ~Lock();

private:
    int fd_;
};

struct Native {
    std::filesystem::path data;
    std::string socket;
    std::string mihomo = "mihomo";
    std::string systemctl = "systemctl";
    std::string journalctl = "journalctl";

    Res<Lock> lock() const;
    Res<Store> store() const;
    Res<Settings> settings() const;
    Res<> validate(std::string_view bytes) const;
    Res<std::filesystem::path> profile_path(std::string_view id) const;
    Res<> add(std::string_view raw, std::string_view name, bool running) const;
    Res<> update(std::string_view id, bool running, const std::optional<std::string>& new_url) const;
    Res<> select(std::string_view id, bool running) const;
    Res<> rename(std::string_view id, std::string_view name) const;
    Res<> remove(std::string_view id) const;
    Res<> change(std::string_view key, std::string_view value, bool running) const;
    Res<> generate() const;
    Res<> service(std::string_view verb) const;
    std::string failure() const;

private:
    Res<Settings> initial_settings() const;
    Res<> seed_geo() const;
    Res<> commit(const Store& store, const Settings& settings, const std::optional<std::pair<std::string, std::string>>& changed, bool running) const;
    Res<> reload_checked(const Settings& settings) const;
};
// Exposed for fixtures: atomic write with mode 0600 and a directory sync.
Res<> replace_file(const std::filesystem::path& path, std::string_view bytes);
Res<> private_dir(const std::filesystem::path& path);
}  // namespace clash
