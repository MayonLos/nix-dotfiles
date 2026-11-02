// Small, secret-free client for the Mihomo controller. It only reaches the given Unix socket and never
// sends Authorization: the socket is the supported local boundary and its API secret stays private.
// Everything here blocks, so call it from workers.
#pragma once
#include <expected>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

#include "model.hpp"
#include "ui/http.hpp"

namespace clash {
// A cancellation flag that a blocked worker can also sleep or poll on.
class Stop {
public:
    Stop();
    ~Stop();
    Stop(const Stop&) = delete;
    Stop& operator=(const Stop&) = delete;
    void stop();
    bool stopped() const { return flag->load(); }
    // Sleeps; true when stopped meanwhile.
    bool wait_ms(int ms) const;
    int fd() const { return fd_; }
    tui::Cancel flag;

private:
    int fd_;
};

struct Client {
    std::string socket;
    tui::Cancel cancel;

    std::expected<Proxies, ApiError> proxies() const;
    std::expected<RuntimeConfig, ApiError> configs() const;
    std::expected<std::string, ApiError> version() const;
    std::expected<void, ApiError> select(const std::string& group, const std::string& node) const;
    std::expected<void, ApiError> reload() const;
    std::expected<uint64_t, ApiError> delay(const std::string& proxy, const std::string& test_url, uint64_t timeout_ms) const;
    std::expected<std::map<std::string, uint64_t>, ApiError> group_delay(const std::string& group, const std::string& url, uint64_t timeout_ms) const;
    std::expected<void, ApiError> close(const std::string& id) const;
    std::expected<void, ApiError> close_all() const;
    std::expected<Providers, ApiError> providers(bool rules) const;
    std::expected<std::vector<Rule>, ApiError> rules() const;
    std::expected<void, ApiError> update_provider(const std::string& name, bool rules) const;
    std::expected<void, ApiError> healthcheck(const std::string& name) const;
    // 0 fake-ip cache, 1 DNS cache, otherwise the Geo databases.
    std::expected<void, ApiError> tool(size_t index) const;
    // Streams newline-delimited JSON until stopped or closed. True once the server accepted the stream.
    bool stream_lines(const std::string& path, const Stop& stop, const std::function<void()>& on_open, const std::function<bool(std::string_view)>& on_line) const;
    // Follows /connections?interval=1000 over a WebSocket; the plain route only answers one snapshot.
    // on_text returns false to stop. Returns when the stream ends or is silent for five seconds.
    void connection_stream(const Stop& stop, const std::function<bool(std::string_view)>& on_text) const;
};
}  // namespace clash
