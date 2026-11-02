#include "net/http.hpp"

#include <curl/curl.h>

#include <algorithm>
#include <array>
#include <memory>
#include <stdexcept>

namespace bili {
const char* const kUserAgent =
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
namespace {
struct State {
    const HttpRequest* request;
    HttpResponse* response;
    size_t received = 0;
    bool too_large = false;
    bool sink_stopped = false;
};
size_t on_body(char* data, size_t size, size_t count, void* user) {
    auto* state = static_cast<State*>(user);
    const size_t bytes = size * count;
    if (state->request->sink) {
        if (!state->request->sink(data, bytes)) {
            state->sink_stopped = true;
            return 0;
        }
        return bytes;
    }
    state->received += bytes;
    if (state->received > state->request->max_bytes) {
        state->too_large = true;
        return 0;
    }
    state->response->body.append(data, bytes);
    return bytes;
}
size_t on_header(char* data, size_t size, size_t count, void* user) {
    auto* state = static_cast<State*>(user);
    const size_t bytes = size * count;
    std::string line(data, bytes);
    static const std::string prefix = "set-cookie:";
    if (line.size() > prefix.size()) {
        std::string head = line.substr(0, prefix.size());
        std::transform(head.begin(), head.end(), head.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (head == prefix) {
            auto value = line.substr(prefix.size());
            value.erase(0, value.find_first_not_of(" \t"));
            value.erase(value.find_last_not_of("\r\n") + 1);
            if (state->response->set_cookies.size() < 32) state->response->set_cookies.push_back(std::move(value));
        }
    }
    return bytes;
}
int on_progress(void* user, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
    const auto* state = static_cast<State*>(user);
    return state->request->cancel && state->request->cancel->load() ? 1 : 0;
}
struct Global {
    Global() { curl_global_init(CURL_GLOBAL_DEFAULT); }
    ~Global() { curl_global_cleanup(); }
};
struct HandleDeleter {
    void operator()(CURL* handle) const { curl_easy_cleanup(handle); }
};
}  // namespace
HttpResponse http_perform(const HttpRequest& request) {
    static Global global;
    thread_local std::unique_ptr<CURL, HandleDeleter> shared(curl_easy_init());
    CURL* curl = shared.get();
    if (!curl) throw std::runtime_error("无法初始化网络客户端");
    curl_easy_reset(curl);
    HttpResponse response;
    State state{&request, &response};
    curl_slist* headers = nullptr;
    for (const auto& header : request.headers) headers = curl_slist_append(headers, header.c_str());
    curl_easy_setopt(curl, CURLOPT_URL, request.url.c_str());
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "https");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, kUserAgent);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, request.timeout_seconds);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &state);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, on_header);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &state);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, on_progress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &state);
    if (request.post || !request.body.empty()) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, request.body.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(request.body.size()));
    }
    const CURLcode code = curl_easy_perform(curl);
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response.status);
    // Detach pointers that die with this call from the reused handle.
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, nullptr);
    curl_slist_free_all(headers);
    if (code == CURLE_ABORTED_BY_CALLBACK) throw std::runtime_error("请求已取消");
    if (state.too_large) throw std::runtime_error("B 站响应超过大小上限");
    if (state.sink_stopped) throw std::runtime_error("数据写入失败");
    if (code != CURLE_OK) throw std::runtime_error(std::string("网络请求失败：") + curl_easy_strerror(code));
    return response;
}
std::string trusted_media_url(const std::string& raw) {
    const std::string input = raw.rfind("//", 0) == 0 ? "https:" + raw : raw;
    struct UrlDeleter {
        void operator()(CURLU* url) const { curl_url_cleanup(url); }
    };
    std::unique_ptr<CURLU, UrlDeleter> url(curl_url());
    if (!url || curl_url_set(url.get(), CURLUPART_URL, input.c_str(), 0) != CURLUE_OK) throw std::runtime_error("媒体地址格式无效");
    const auto part = [&](CURLUPart which) {
        char* value = nullptr;
        std::string out;
        if (curl_url_get(url.get(), which, &value, 0) == CURLUE_OK && value) out = value;
        curl_free(value);
        return out;
    };
    const std::string scheme = part(CURLUPART_SCHEME);
    if (scheme == "http") curl_url_set(url.get(), CURLUPART_SCHEME, "https", 0);
    else if (scheme != "https") throw std::runtime_error("拒绝非 B 站媒体地址");
    const std::string host = part(CURLUPART_HOST);
    const std::string port = part(CURLUPART_PORT);
    bool allowed = false;
    for (const std::string domain : {"bilivideo.com", "bilivideo.cn", "hdslb.com", "bilibili.com"}) {
        const std::string suffix = "." + domain;
        allowed = allowed || host == domain || (host.size() > suffix.size() && host.compare(host.size() - suffix.size(), suffix.size(), suffix) == 0);
    }
    if (!allowed || !part(CURLUPART_USER).empty() || !part(CURLUPART_PASSWORD).empty() ||
        (!port.empty() && port != "443" && port != "4483" && port != "8082")) {
        throw std::runtime_error("拒绝非 B 站媒体地址");
    }
    return part(CURLUPART_URL);
}
}  // namespace bili
