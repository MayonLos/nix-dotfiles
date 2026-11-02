// Blocking HTTPS over libcurl. Never follows redirects, never reports URLs in errors.
#pragma once
#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace bili {
using CancelFlag = std::shared_ptr<std::atomic<bool>>;
inline CancelFlag make_cancel() { return std::make_shared<std::atomic<bool>>(false); }
extern const char* const kUserAgent;
struct HttpRequest {
    std::string url;
    std::string body;  // Non-empty or post=true sends a form POST.
    bool post = false;
    std::vector<std::string> headers;
    size_t max_bytes = 8 * 1024 * 1024;
    long timeout_seconds = 20;
    CancelFlag cancel;
    // Streams instead of buffering; returning false aborts the transfer.
    std::function<bool(const char*, size_t)> sink;
};
struct HttpResponse {
    long status = 0;
    std::string body;
    std::vector<std::string> set_cookies;
};
HttpResponse http_perform(const HttpRequest& request);
// Host checks for CDN URLs. Returns a normalized https URL or throws.
std::string trusted_media_url(const std::string& raw);
}  // namespace bili
