#include "ui/http.hpp"

#include <curl/curl.h>

#include <memory>
#include <stdexcept>

namespace tui {
namespace {
struct Context {
    const HttpRequest* request;
    std::string* out;
};
size_t on_body(char* data, size_t size, size_t count, void* user) {
    auto* context = static_cast<Context*>(user);
    const size_t total = size * count;
    if (context->request->on_data) return context->request->on_data(std::string_view(data, total)) ? total : 0;
    context->out->append(data, total);
    return total;
}
int on_progress(void* user, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
    const auto* request = static_cast<const HttpRequest*>(user);
    return request->cancel && request->cancel->load() ? 1 : 0;
}
}  // namespace
HttpReply unix_http(const HttpRequest& request) {
    const std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl) throw std::runtime_error("curl init failed");
    CURL* handle = curl.get();
    HttpReply reply;
    Context context{&request, &reply.body};
    const std::string url = "http://localhost" + request.path;
    curl_easy_setopt(handle, CURLOPT_UNIX_SOCKET_PATH, request.socket.c_str());
    curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
    curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST, request.method.c_str());
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, request.timeout_ms);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, on_body);
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &context);
    curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(handle, CURLOPT_XFERINFOFUNCTION, on_progress);
    curl_easy_setopt(handle, CURLOPT_XFERINFODATA, const_cast<HttpRequest*>(&request));
    curl_slist* raw = nullptr;
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)> list(raw, curl_slist_free_all);
    const auto add = [&](const std::string& header) { list.reset(curl_slist_append(list.release(), header.c_str())); };
    if (!request.body.empty()) {
        add("Content-Type: " + request.content_type);
        curl_easy_setopt(handle, CURLOPT_POSTFIELDS, request.body.data());
        curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(request.body.size()));
    }
    if (!request.bearer.empty()) add("Authorization: Bearer " + request.bearer);
    if (list) curl_easy_setopt(handle, CURLOPT_HTTPHEADER, list.get());
    const CURLcode code = curl_easy_perform(handle);
    const bool stopped = code == CURLE_WRITE_ERROR || code == CURLE_ABORTED_BY_CALLBACK;
    if (code != CURLE_OK && !stopped) throw std::runtime_error(curl_easy_strerror(code));
    curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &reply.status);
    return reply;
}
}  // namespace tui
