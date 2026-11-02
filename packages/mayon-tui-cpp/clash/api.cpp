#include "api.hpp"

#include <poll.h>
#include <sys/eventfd.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <stdexcept>

#include "ui/terminal.hpp"

namespace clash {
Stop::Stop() : flag(std::make_shared<std::atomic<bool>>(false)), fd_(eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK)) {}
Stop::~Stop() { ::close(fd_); }
void Stop::stop() {
    flag->store(true);
    const uint64_t one = 1;
    [[maybe_unused]] const auto ignored = ::write(fd_, &one, sizeof one);
}
bool Stop::wait_ms(int ms) const {
    if (stopped()) return true;
    pollfd item{fd_, POLLIN, 0};
    ::poll(&item, 1, ms);
    return stopped();
}

namespace {
std::expected<tui::HttpReply, ApiError> send(const Client& client, const std::string& method, std::string path, std::string body, long timeout_ms) {
    tui::HttpRequest request;
    request.socket = client.socket;
    request.method = method;
    request.path = std::move(path);
    request.body = std::move(body);
    request.timeout_ms = timeout_ms;
    request.cancel = client.cancel;
    try {
        auto reply = tui::unix_http(request);
        if (reply.status == 0) return std::unexpected(ApiError::Transport);
        return reply;
    } catch (const std::exception&) {
        return std::unexpected(ApiError::Transport);
    }
}
bool success(long status) { return status >= 200 && status < 300; }
template <class Parse>
auto json_call(const Client& client, std::string path, long timeout_ms, Parse parse) -> std::expected<decltype(parse(std::string_view{})), ApiError> {
    const auto reply = send(client, "GET", std::move(path), "", timeout_ms);
    if (!reply) return std::unexpected(reply.error());
    if (!success(reply->status)) return std::unexpected(ApiError::Rejected);
    try {
        return parse(reply->body);
    } catch (const std::exception&) {
        return std::unexpected(ApiError::InvalidResponse);
    }
}
std::expected<void, ApiError> empty_call(const Client& client, const std::string& method, std::string path, std::string body, long timeout_ms) {
    const auto reply = send(client, method, std::move(path), std::move(body), timeout_ms);
    if (!reply) return std::unexpected(reply.error());
    if (!success(reply->status)) return std::unexpected(ApiError::Rejected);
    return {};
}
std::string json_quote(std::string_view value) {
    std::string out = "\"";
    for (const char c : value) {
        const auto byte = static_cast<unsigned char>(c);
        if (c == '"' || c == '\\') {
            out += '\\';
            out += c;
        } else if (byte < 0x20) {
            static constexpr char hex[] = "0123456789abcdef";
            out += "\\u00";
            out += hex[byte >> 4];
            out += hex[byte & 15];
        } else {
            out += c;
        }
    }
    return out + "\"";
}
constexpr long kDefaultTimeout = 8000;
constexpr long kProviderTimeout = 180000;
}  // namespace

std::expected<Proxies, ApiError> Client::proxies() const { return json_call(*this, "/proxies", kDefaultTimeout, parse_proxies); }
std::expected<RuntimeConfig, ApiError> Client::configs() const { return json_call(*this, "/configs", kDefaultTimeout, parse_config); }
std::expected<std::string, ApiError> Client::version() const { return json_call(*this, "/version", kDefaultTimeout, parse_version); }
std::expected<void, ApiError> Client::select(const std::string& group, const std::string& node) const {
    return empty_call(*this, "PUT", encode_path({"proxies", group}), std::string("{\"name\":") + json_quote(node) + "}", kDefaultTimeout);
}
std::expected<void, ApiError> Client::reload() const { return empty_call(*this, "PUT", "/configs?force=true", "{}", 60000); }
std::expected<uint64_t, ApiError> Client::delay(const std::string& proxy, const std::string& test_url, uint64_t timeout_ms) const {
    const auto url = parse_url(test_url);
    if (!url) return std::unexpected(ApiError::InvalidEndpoint);
    const std::string path = encode_path({"proxies", proxy, "delay"}) + "?url=" + encode_query(url->text) + "&timeout=" + std::to_string(timeout_ms);
    return json_call(*this, path, static_cast<long>(timeout_ms) + 2000, parse_delay);
}
std::expected<std::map<std::string, uint64_t>, ApiError> Client::group_delay(const std::string& group, const std::string& url, uint64_t timeout_ms) const {
    const std::string path = encode_path({"group", group, "delay"}) + "?url=" + encode_query(url) + "&timeout=" + std::to_string(timeout_ms);
    return json_call(*this, path, static_cast<long>(timeout_ms) + 2000, parse_group_delay);
}
std::expected<void, ApiError> Client::close(const std::string& id) const { return empty_call(*this, "DELETE", encode_path({"connections", id}), "", kDefaultTimeout); }
std::expected<void, ApiError> Client::close_all() const { return empty_call(*this, "DELETE", "/connections", "", kDefaultTimeout); }
std::expected<Providers, ApiError> Client::providers(bool rules) const { return json_call(*this, rules ? "/providers/rules" : "/providers/proxies", kDefaultTimeout, parse_providers); }
std::expected<std::vector<Rule>, ApiError> Client::rules() const { return json_call(*this, "/rules", kDefaultTimeout, parse_rules); }
std::expected<void, ApiError> Client::update_provider(const std::string& name, bool rules) const {
    return empty_call(*this, "PUT", encode_path({"providers", rules ? "rules" : "proxies", name}), "", kProviderTimeout);
}
std::expected<void, ApiError> Client::healthcheck(const std::string& name) const {
    return empty_call(*this, "GET", encode_path({"providers", "proxies", name, "healthcheck"}), "", kProviderTimeout);
}
std::expected<void, ApiError> Client::tool(size_t index) const {
    const char* path = index == 0 ? "/cache/fakeip/flush" : index == 1 ? "/cache/dns/flush" : "/configs/geo";
    return empty_call(*this, "POST", path, "", index == 2 ? kProviderTimeout : kDefaultTimeout);
}
bool Client::stream_lines(const std::string& path, const Stop& stop, const std::function<void()>& on_open, const std::function<bool(std::string_view)>& on_line) const {
    tui::HttpRequest request;
    request.socket = socket;
    request.path = path;
    request.timeout_ms = 0;
    request.cancel = stop.flag;
    std::string buffer;
    bool opened = false;
    request.on_data = [&](std::string_view chunk) {
        if (stop.stopped() || buffer.size() + chunk.size() > 65536) return false;
        if (!opened) {
            opened = true;
            if (on_open) on_open();
        }
        buffer.append(chunk);
        size_t end = 0;
        while ((end = buffer.find('\n')) != std::string::npos) {
            if (!on_line(std::string_view(buffer).substr(0, end))) return false;
            buffer.erase(0, end + 1);
        }
        return true;
    };
    try {
        tui::unix_http(request);
    } catch (const std::exception&) {
        return opened;
    }
    return opened;
}

namespace {
class WebSocket {
public:
    explicit WebSocket(int fd) : fd_(fd) {}
    ~WebSocket() { ::close(fd_); }
    WebSocket(const WebSocket&) = delete;
    WebSocket& operator=(const WebSocket&) = delete;
    std::string buffer;
    // Waits for bytes; false on stop, silence or close.
    bool fill(const Stop& stop, int timeout_ms) {
        pollfd items[2]{{fd_, POLLIN, 0}, {stop.fd(), POLLIN, 0}};
        if (::poll(items, 2, timeout_ms) <= 0 || (items[1].revents & POLLIN)) return false;
        char chunk[65536];
        const ssize_t got = ::recv(fd_, chunk, sizeof chunk, MSG_DONTWAIT);
        if (got <= 0) return false;
        buffer.append(chunk, static_cast<size_t>(got));
        return true;
    }
    bool send_frame(unsigned char opcode, std::string_view payload) {
        std::string frame;
        frame += static_cast<char>(0x80 | opcode);
        if (payload.size() >= 126) return false;  // Only short control frames are ever sent.
        frame += static_cast<char>(0x80 | payload.size());
        unsigned char mask[4]{};
        if (getrandom(mask, sizeof mask, 0) != sizeof mask) return false;
        frame.append(reinterpret_cast<const char*>(mask), sizeof mask);
        for (size_t i = 0; i < payload.size(); ++i) frame += static_cast<char>(static_cast<unsigned char>(payload[i]) ^ mask[i % 4]);
        return send_all(frame);
    }
    bool send_all(std::string_view data) {
        while (!data.empty()) {
            const ssize_t sent = ::send(fd_, data.data(), data.size(), MSG_NOSIGNAL);
            if (sent <= 0) return false;
            data.remove_prefix(static_cast<size_t>(sent));
        }
        return true;
    }

private:
    int fd_;
};
constexpr size_t kMaxFrame = 16 * 1024 * 1024;
}  // namespace
void Client::connection_stream(const Stop& stop, const std::function<bool(std::string_view)>& on_text) const {
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (socket.size() >= sizeof address.sun_path) return;
    std::memcpy(address.sun_path, socket.data(), socket.size());
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return;
    WebSocket ws(fd);
    if (::connect(fd, reinterpret_cast<const sockaddr*>(&address), sizeof address) != 0) return;
    unsigned char nonce[16]{};
    if (getrandom(nonce, sizeof nonce, 0) != sizeof nonce) return;
    const std::string key = tui::base64(std::string_view(reinterpret_cast<const char*>(nonce), sizeof nonce));
    const std::string handshake = "GET /connections?interval=1000 HTTP/1.1\r\nHost: mihomo\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: " + key + "\r\n\r\n";
    if (!ws.send_all(handshake)) return;
    // The peer is the local socket's owner, so a 101 status is enough; the accept hash proves nothing here.
    size_t header_end = 0;
    while ((header_end = ws.buffer.find("\r\n\r\n")) == std::string::npos) {
        if (ws.buffer.size() > 65536 || !ws.fill(stop, 3000)) return;
    }
    if (ws.buffer.compare(0, 12, "HTTP/1.1 101") != 0) return;
    ws.buffer.erase(0, header_end + 4);
    std::string message;
    while (!stop.stopped()) {
        // A complete frame header and payload, or read more.
        const auto need_more = [&] { return !ws.fill(stop, 5000); };
        if (ws.buffer.size() < 2) {
            if (need_more()) return;
            continue;
        }
        const auto first = static_cast<unsigned char>(ws.buffer[0]);
        const auto second = static_cast<unsigned char>(ws.buffer[1]);
        size_t header = 2;
        uint64_t length = second & 0x7F;
        if (length >= 126) {
            const size_t extra = length == 126 ? 2 : 8;
            if (ws.buffer.size() < 2 + extra) {
                if (need_more()) return;
                continue;
            }
            length = 0;
            for (size_t i = 0; i < extra; ++i) length = (length << 8) | static_cast<unsigned char>(ws.buffer[2 + i]);
            header += extra;
        }
        if (second & 0x80 || length > kMaxFrame) return;  // A server must not mask.
        if (ws.buffer.size() < header + length) {
            if (need_more()) return;
            continue;
        }
        const std::string payload = ws.buffer.substr(header, length);
        ws.buffer.erase(0, header + length);
        const unsigned char opcode = first & 0x0F;
        if (opcode == 8) {
            ws.send_frame(8, "");
            return;
        }
        if (opcode == 9) {
            if (payload.size() >= 126 || !ws.send_frame(10, payload)) return;
            continue;
        }
        if (opcode != 0 && opcode != 1) continue;
        message += payload;
        if (message.size() > kMaxFrame) return;
        if (first & 0x80) {
            if (!on_text(message)) break;
            message.clear();
        }
    }
    ws.send_frame(8, "");
}
}  // namespace clash
