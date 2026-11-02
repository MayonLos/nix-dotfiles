// Blocking HTTP over a local Unix socket for Docker and Mihomo. Call from workers, never the UI thread.
#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

namespace tui {
using Cancel = std::shared_ptr<std::atomic<bool>>;
struct HttpReply {
    long status = 0;
    std::string body;
};
struct HttpRequest {
    std::string socket;
    std::string method = "GET";
    std::string path;  // Includes the query.
    std::string body;
    std::string content_type = "application/json";
    std::string bearer;
    long timeout_ms = 30000;  // 0 for streams.
    Cancel cancel;
    // When set the body streams here instead of into the reply; return false to stop.
    std::function<bool(std::string_view)> on_data;
};
// Throws std::runtime_error when the socket cannot be reached.
HttpReply unix_http(const HttpRequest& request);
}  // namespace tui
