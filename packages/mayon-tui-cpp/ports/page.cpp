#include "page.hpp"

#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <limits>
#include <nlohmann/json.hpp>
#include <sstream>
#include <thread>

#include "app.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"
#include "ui/widgets.hpp"

using ftxui::Screen;
using tui::InputEvent;
using tui::Key;
using tui::KeyCode;
using tui::Rect;
using tui::Style;
using Clock = std::chrono::steady_clock;

namespace ports {
namespace {

std::optional<std::string> read_file(const std::filesystem::path& path) {
    const std::unique_ptr<std::FILE, int (*)(std::FILE*)> file(std::fopen(path.c_str(), "rb"), std::fclose);
    if (!file) return std::nullopt;
    std::string out;
    char buffer[65536];
    while (const size_t got = std::fread(buffer, 1, sizeof buffer, file.get())) out.append(buffer, got);
    if (std::ferror(file.get())) return std::nullopt;
    return out;
}

std::optional<uint64_t> parse_uint(std::string_view text, int base) {
    if (text.empty()) return std::nullopt;
    uint64_t value = 0;
    const auto* first = text.data();
    const auto* last = text.data() + text.size();
    if (base == 10 && *first == '+') ++first;
    const auto result = std::from_chars(first, last, value, base);
    if (result.ec != std::errc{} || result.ptr != last) return std::nullopt;
    return value;
}

std::string ipv4_text(uint32_t value) {
    std::string out;
    for (int i = 0; i < 4; ++i) {
        if (i) out += '.';
        out += std::to_string((value >> (i * 8)) & 0xFF);
    }
    return out;
}

std::string ipv6_text(const std::array<uint8_t, 16>& bytes) {
    std::array<uint16_t, 8> segments{};
    for (size_t i = 0; i < 8; ++i) segments[i] = static_cast<uint16_t>((bytes[i * 2] << 8) | bytes[i * 2 + 1]);
    // Rust's std prints IPv4-mapped addresses with a dotted quad.
    if (segments[0] == 0 && segments[1] == 0 && segments[2] == 0 && segments[3] == 0 && segments[4] == 0 &&
        segments[5] == 0xFFFF) {
        return "::ffff:" + std::to_string(bytes[12]) + "." + std::to_string(bytes[13]) + "." + std::to_string(bytes[14]) +
               "." + std::to_string(bytes[15]);
    }
    size_t best = 8, best_len = 0;
    for (size_t i = 0; i < 8;) {
        if (segments[i] != 0) {
            ++i;
            continue;
        }
        const size_t start = i;
        while (i < 8 && segments[i] == 0) ++i;
        if (i - start > best_len) {
            best = start;
            best_len = i - start;
        }
    }
    if (best_len < 2) best = 8;
    char buffer[8];
    std::string out;
    for (size_t i = 0; i < 8;) {
        if (i == best) {
            out += "::";
            i += best_len;
            continue;
        }
        if (!out.empty() && out.back() != ':') out += ':';
        std::snprintf(buffer, sizeof buffer, "%x", segments[i]);
        out += buffer;
        ++i;
    }
    return out;
}

std::string lossy_utf8(std::string_view bytes) { return tui::encode(tui::decode(bytes)); }

std::vector<std::string> passwd_fields(const std::string& line) {
    std::vector<std::string> out;
    std::string field;
    for (const char ch : line) {
        if (ch == ':') {
            out.push_back(field);
            field.clear();
        } else {
            field += ch;
        }
    }
    out.push_back(field);
    return out;
}

void set_default_descriptors() {
    const int fd = ::open("/dev/null", O_RDWR);
    if (fd < 0) return;
    ::dup2(fd, STDIN_FILENO);
    ::dup2(fd, STDOUT_FILENO);
    ::dup2(fd, STDERR_FILENO);
    if (fd > STDERR_FILENO) ::close(fd);
}

bool spawn_detached(const std::string& program, const std::string& argument) {
    const pid_t pid = ::fork();
    if (pid < 0) return false;
    if (pid == 0) {
        const pid_t inner = ::fork();
        if (inner < 0) ::_exit(127);
        if (inner > 0) ::_exit(0);
        set_default_descriptors();
        ::execlp(program.c_str(), program.c_str(), argument.c_str(), static_cast<char*>(nullptr));
        ::_exit(127);
    }
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    return true;
}

bool run_status(const std::string& program, const std::string& argument) {
    const pid_t pid = ::fork();
    if (pid < 0) return false;
    if (pid == 0) {
        set_default_descriptors();
        ::execlp(program.c_str(), program.c_str(), argument.c_str(), static_cast<char*>(nullptr));
        ::_exit(127);
    }
    int status = 0;
    while (::waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

}  // namespace

SelectionKey Listener::key() const { return {protocol, port, pid, inode}; }

std::optional<std::string> decode_addr(std::string_view hex, bool ipv6) {
    if (ipv6) {
        if (hex.size() != 32) return std::nullopt;
        std::array<uint8_t, 16> bytes{};
        for (size_t chunk = 0; chunk < 4; ++chunk) {
            const auto value = parse_uint(hex.substr(chunk * 8, 8), 16);
            if (!value || *value > 0xFFFFFFFF) return std::nullopt;
            for (size_t i = 0; i < 4; ++i) bytes[chunk * 4 + i] = static_cast<uint8_t>((*value >> (i * 8)) & 0xFF);
        }
        return ipv6_text(bytes);
    }
    const auto value = parse_uint(hex, 16);
    if (!value || *value > 0xFFFFFFFF) return std::nullopt;
    return ipv4_text(static_cast<uint32_t>(*value));
}

std::optional<std::vector<SocketRow>> socket_rows(const std::filesystem::path& path, const std::string& protocol,
                                                  bool ipv6) {
    const auto source = read_file(path);
    if (!source) return std::nullopt;
    std::vector<SocketRow> out;
    std::istringstream lines(*source);
    std::string line;
    std::getline(lines, line);
    while (std::getline(lines, line)) {
        std::istringstream fields(line);
        std::vector<std::string> cells;
        std::string cell;
        while (fields >> cell) cells.push_back(cell);
        if (cells.size() < 10) continue;
        if ((protocol == "TCP" && cells[3] != "0A") || (protocol == "UDP" && cells[3] != "07")) continue;
        const auto split = cells[1].rfind(':');
        if (split == std::string::npos) continue;
        const auto address = decode_addr(std::string_view(cells[1]).substr(0, split), ipv6);
        if (!address) continue;
        const auto port = parse_uint(std::string_view(cells[1]).substr(split + 1), 16);
        if (!port || *port == 0 || *port > 0xFFFF) continue;
        const auto inode = parse_uint(cells[9], 10);
        if (!inode) continue;
        out.push_back(SocketRow{protocol, *address, static_cast<uint16_t>(*port), *inode});
    }
    return out;
}

std::optional<ProcDetails> proc_details(int32_t pid) {
    const std::filesystem::path root = std::filesystem::path("/proc") / std::to_string(pid);
    const auto stat = read_file(root / "stat");
    if (!stat) return std::nullopt;
    const auto end = stat->rfind(')');
    if (end == std::string::npos) return std::nullopt;
    std::istringstream rest(stat->substr(end + 2));
    std::vector<std::string> fields;
    std::string field;
    while (rest >> field) fields.push_back(field);
    if (fields.size() <= 19) return std::nullopt;
    std::optional<int32_t> parent;
    if (const auto value = parse_uint(fields[1], 10);
        value && *value <= static_cast<uint64_t>(std::numeric_limits<int32_t>::max()))
        parent = static_cast<int32_t>(*value);
    const auto start = parse_uint(fields[19], 10);
    if (!start) return std::nullopt;
    const auto status = read_file(root / "status");
    if (!status) return std::nullopt;
    std::optional<uint32_t> uid;
    std::istringstream status_lines(*status);
    std::string line;
    while (std::getline(status_lines, line)) {
        if (!line.starts_with("Uid:")) continue;
        std::istringstream values(line.substr(4));
        std::string first;
        if (values >> first) {
            if (const auto value = parse_uint(first, 10); value && *value <= 0xFFFFFFFF)
                uid = static_cast<uint32_t>(*value);
        }
        break;
    }
    if (!uid) return std::nullopt;
    std::string user = std::to_string(*uid);
    if (const auto passwd = read_file("/etc/passwd")) {
        std::istringstream entries(*passwd);
        std::string entry;
        while (std::getline(entries, entry)) {
            const auto parts = passwd_fields(entry);
            if (parts.size() > 2 && parts[2] == std::to_string(*uid)) {
                user = parts[0];
                break;
            }
        }
    }
    std::string comm = "?";
    if (const auto raw = read_file(root / "comm")) comm = tui::trim(*raw);
    std::string command;
    if (const auto raw = read_file(root / "cmdline")) {
        const std::string text = lossy_utf8(*raw);
        std::string part;
        for (size_t i = 0; i <= text.size(); ++i) {
            if (i == text.size() || text[i] == '\0') {
                if (!part.empty()) {
                    if (!command.empty()) command += ' ';
                    command += part;
                    part.clear();
                }
            } else {
                part += text[i];
            }
        }
    }
    if (command.empty()) command = comm;
    std::string cwd = "系统 / 不可见";
    std::error_code error;
    if (const auto link = std::filesystem::read_symlink(root / "cwd", error); !error) cwd = link.string();
    return ProcDetails{comm, command, user, cwd, parent, *start, *uid};
}

bool same_process(const ProcDetails& details, uint32_t uid, uint64_t start) {
    return details.uid == uid && details.start == start;
}

std::string boot_age(uint64_t start_ticks) {
    double uptime = 0.0;
    if (const auto text = read_file("/proc/uptime")) {
        std::istringstream first(*text);
        first >> uptime;
    }
    const long raw_ticks = ::sysconf(_SC_CLK_TCK);
    const double ticks = raw_ticks > 0 ? static_cast<double>(raw_ticks) : 1.0;
    const double elapsed = std::max(uptime - static_cast<double>(start_ticks) / ticks, 0.0);
    const uint64_t seconds = static_cast<uint64_t>(elapsed);
    if (seconds < 60) return std::to_string(seconds) + "s";
    if (seconds < 3600) return std::to_string(seconds / 60) + "m";
    if (seconds < 86400) return std::to_string(seconds / 3600) + "h" + std::to_string((seconds % 3600) / 60) + "m";
    return std::to_string(seconds / 86400) + "d" + std::to_string((seconds % 86400) / 3600) + "h";
}

std::vector<Listener> scan_proc() {
    struct Raw {
        std::string protocol;
        std::string address;
        uint16_t port;
        uint64_t inode;
    };
    std::vector<Raw> raw;
    const std::array<std::tuple<const char*, const char*, bool>, 4> sources{
        {{"tcp", "TCP", false}, {"tcp6", "TCP", true}, {"udp", "UDP", false}, {"udp6", "UDP", true}}};
    for (const auto& [file, protocol, ipv6] : sources) {
        if (const auto rows = socket_rows(std::filesystem::path("/proc/net") / file, protocol, ipv6)) {
            for (const SocketRow& row : *rows) raw.push_back(Raw{row.protocol, row.address, row.port, row.inode});
        }
    }
    std::map<uint64_t, int32_t> inode_pid;
    std::error_code error;
    for (std::filesystem::directory_iterator entries("/proc", error), end; !error && entries != end;
         entries.increment(error)) {
        const std::string name = entries->path().filename().string();
        const auto pid = parse_uint(name, 10);
        if (!pid || *pid > static_cast<uint64_t>(std::numeric_limits<int32_t>::max())) continue;
        std::error_code fd_error;
        for (std::filesystem::directory_iterator fds(entries->path() / "fd", fd_error), fd_end;
             !fd_error && fds != fd_end; fds.increment(fd_error)) {
            std::error_code link_error;
            const auto link = std::filesystem::read_symlink(fds->path(), link_error);
            if (link_error) continue;
            const std::string target = link.string();
            if (!target.starts_with("socket:[") || !target.ends_with(']')) continue;
            const auto inode = parse_uint(std::string_view(target).substr(8, target.size() - 9), 10);
            if (inode) inode_pid.emplace(*inode, static_cast<int32_t>(*pid));
        }
    }
    const auto own = static_cast<uint32_t>(::geteuid());
    std::vector<Listener> out;
    out.reserve(raw.size());
    for (const Raw& socket : raw) {
        const auto found = inode_pid.find(socket.inode);
        const std::optional<int32_t> pid =
            found == inode_pid.end() ? std::nullopt : std::optional<int32_t>(found->second);
        const auto details = pid ? proc_details(*pid) : std::nullopt;
        const bool accessible = details && details->uid == own;
        Listener row;
        row.protocol = socket.protocol;
        row.address = socket.address;
        row.port = socket.port;
        row.inode = socket.inode;
        row.pid = pid;
        if (details) {
            row.process = tui::clean(details->comm);
            row.command = tui::clean(details->command);
            row.user = accessible ? tui::clean(details->user) : "系统";
            row.cwd = accessible ? tui::clean(details->cwd) : "系统 / 不可见";
            row.parent = accessible ? details->parent : std::nullopt;
            row.start_ticks = details->start;
            row.uid = details->uid;
            row.age = boot_age(details->start);
        } else {
            row.process = "系统";
            row.command = "系统 / 不可见";
            row.user = "系统";
            row.cwd = "系统 / 不可见";
            row.age = "--";
        }
        out.push_back(std::move(row));
    }
    std::stable_sort(out.begin(), out.end(), [](const Listener& a, const Listener& b) {
        if (a.port != b.port) return a.port < b.port;
        if (a.protocol != b.protocol) return a.protocol < b.protocol;
        return a.address < b.address;
    });
    return out;
}

std::string scope(const std::string& address) {
    const auto ip = parse_ip(address);
    if (!ip) return "指定接口";
    if (ip->unspecified()) return "对外";
    if (ip->loopback()) return "本机";
    return "指定接口";
}

bool Ip::unspecified() const {
    for (size_t i = 0; i < (v6 ? 16u : 4u); ++i)
        if (bytes[i] != 0) return false;
    return true;
}
bool Ip::loopback() const {
    if (v6) {
        for (size_t i = 0; i < 15; ++i)
            if (bytes[i] != 0) return false;
        return bytes[15] == 1;
    }
    return bytes[0] == 127;
}

std::optional<Ip> parse_ip(std::string_view text) {
    Ip out;
    if (text.find(':') != std::string_view::npos) {
        out.v6 = true;
        in6_addr address{};
        const std::string copy(text);
        if (::inet_pton(AF_INET6, copy.c_str(), &address) != 1) return std::nullopt;
        std::memcpy(out.bytes.data(), &address, 16);
        return out;
    }
    in_addr address{};
    const std::string copy(text);
    if (::inet_pton(AF_INET, copy.c_str(), &address) != 1) return std::nullopt;
    std::memcpy(out.bytes.data(), &address, 4);
    return out;
}

std::optional<std::filesystem::path> docker_socket_path(std::optional<std::string> docker_host,
                                                        std::optional<std::filesystem::path> runtime, bool force) {
    if (docker_host) {
        if (!docker_host->starts_with("unix://")) return std::nullopt;
        const std::filesystem::path path = docker_host->substr(7);
        if (runtime) {
            if (path == *runtime / "docker.sock" && !force &&
                !std::filesystem::exists(*runtime / "docker-private.sock"))
                return std::nullopt;
        }
        return path;
    }
    if (!runtime) return std::nullopt;
    if (!force && !std::filesystem::exists(*runtime / "docker-private.sock")) return std::nullopt;
    return *runtime / "docker.sock";
}

std::string docker_for_listener(const DockerBindings& bindings, const std::string& protocol, uint16_t port,
                                const std::string& address) {
    const auto listener = parse_ip(address);
    if (!listener) return {};
    const auto found = bindings.entries.find(PortKey{protocol, port});
    if (found == bindings.entries.end()) return {};
    std::vector<std::string> names;
    for (const auto& [published, name] : found->second) {
        bool compatible = false;
        if (published) {
            if (published->unspecified()) compatible = published->v6 == listener->v6;
            else compatible = *published == *listener;
        } else {
            compatible = listener->unspecified();
        }
        if (compatible && std::find(names.begin(), names.end(), name) == names.end()) names.push_back(name);
    }
    std::string out;
    for (const std::string& name : names) {
        if (!out.empty()) out += ", ";
        out += name;
    }
    return out;
}

namespace {
struct DockerPort {
    std::optional<uint16_t> public_port;
    std::optional<Ip> ip;
    std::string type;
};

std::optional<DockerPort> docker_port(const nlohmann::json& value) {
    if (!value.is_object()) return std::nullopt;
    DockerPort out;
    if (value.contains("PublicPort") && !value["PublicPort"].is_null()) {
        const auto& port = value["PublicPort"];
        if (!port.is_number_integer() && !port.is_number_unsigned()) return std::nullopt;
        const auto number = port.get<int64_t>();
        if (number < 0 || number > 0xFFFF) return std::nullopt;
        out.public_port = static_cast<uint16_t>(number);
    }
    if (value.contains("IP") && !value["IP"].is_null()) {
        if (!value["IP"].is_string()) return std::nullopt;
        out.ip = parse_ip(value["IP"].get<std::string>());
    }
    if (value.contains("Type") && !value["Type"].is_null()) {
        if (!value["Type"].is_string()) return std::nullopt;
        out.type = value["Type"].get<std::string>();
    }
    return out;
}
}  // namespace

DockerBindings parse_docker_response(std::string_view response) {
    DockerBindings out;
    const auto split = response.find("\r\n\r\n");
    if (split == std::string_view::npos) return out;
    std::string headers(response.substr(0, split));
    std::transform(headers.begin(), headers.end(), headers.begin(),
                   [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    std::string_view body = response.substr(split + 4);
    std::string decoded;
    if (headers.find("transfer-encoding: chunked") != std::string::npos) {
        size_t at = 0;
        while (at < body.size()) {
            const auto end = body.find("\r\n", at);
            if (end == std::string_view::npos) break;
            auto size_text = body.substr(at, end - at);
            const auto semicolon = size_text.find(';');
            if (semicolon != std::string_view::npos) size_text = size_text.substr(0, semicolon);
            const auto size = parse_uint(size_text, 16);
            if (!size) break;
            at = end + 2;
            if (*size == 0 || body.size() < at + *size + 2) break;
            decoded.append(body.substr(at, *size));
            at += *size + 2;
            if (decoded.size() > 8 * 1024 * 1024) break;
        }
        body = decoded;
    }
    nlohmann::json document;
    try {
        document = nlohmann::json::parse(body);
    } catch (const nlohmann::json::exception&) {
        return out;
    }
    if (!document.is_array()) return out;
    for (const auto& container : document) {
        if (!container.is_object()) return DockerBindings{};
        std::vector<std::string> names;
        if (container.contains("Names")) {
            if (!container["Names"].is_array()) return DockerBindings{};
            for (const auto& name : container["Names"]) {
                if (!name.is_string()) return DockerBindings{};
                names.push_back(name.get<std::string>());
            }
        }
        std::vector<DockerPort> ports;
        if (container.contains("Ports")) {
            if (!container["Ports"].is_array()) return DockerBindings{};
            for (const auto& port : container["Ports"]) {
                const auto parsed = docker_port(port);
                if (!parsed) return DockerBindings{};
                ports.push_back(*parsed);
            }
        }
        if (names.empty()) continue;
        std::string name = names.front();
        while (!name.empty() && name.front() == '/') name.erase(name.begin());
        if (name.empty()) continue;
        for (const DockerPort& port : ports) {
            if (!port.public_port) continue;
            out.entries[PortKey{port.type, *port.public_port}].emplace_back(port.ip, tui::clean(name));
        }
    }
    return out;
}

namespace {
bool wait_socket(int fd, short events, Clock::time_point deadline, const std::atomic<bool>* cancel) {
    while (true) {
        if (cancel && cancel->load()) return false;
        if (Clock::now() >= deadline) return false;
        pollfd entry{fd, events, 0};
        const int ready = ::poll(&entry, 1, 50);
        if (ready > 0) return true;
        if (ready < 0 && errno != EINTR) return false;
    }
}
}  // namespace

DockerBindings docker_names(bool force, const std::atomic<bool>* cancel) {
    const char* host_env = std::getenv("DOCKER_HOST");
    std::optional<std::string> docker_host;
    if (host_env) docker_host = std::string(host_env);
    const char* runtime_env = std::getenv("XDG_RUNTIME_DIR");
    std::optional<std::filesystem::path> runtime;
    if (runtime_env) runtime = std::filesystem::path(runtime_env);
    const auto path = docker_socket_path(docker_host, runtime, force);
    if (!path) return {};
    std::error_code error;
    if (!std::filesystem::exists(*path, error)) return {};
    const std::string socket_path = path->string();
    sockaddr_un address{};
    if (socket_path.size() >= sizeof(address.sun_path)) return {};
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0) return {};
    address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, socket_path.c_str(), socket_path.size() + 1);
    const auto deadline = Clock::now() + std::chrono::seconds(1);
    int rc = ::connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof address);
    if (rc != 0 && errno == EINPROGRESS) {
        if (!wait_socket(fd, POLLOUT, deadline, cancel)) {
            ::close(fd);
            return {};
        }
        int socket_error = 0;
        socklen_t length = sizeof socket_error;
        if (::getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &length) != 0 || socket_error != 0) {
            ::close(fd);
            return {};
        }
        rc = 0;
    }
    if (rc != 0) {
        ::close(fd);
        return {};
    }
    constexpr std::string_view request =
        "GET /containers/json?all=1 HTTP/1.1\r\nHost: docker\r\nConnection: close\r\n\r\n";
    size_t sent = 0;
    while (sent < request.size()) {
        const ssize_t written = ::send(fd, request.data() + sent, request.size() - sent, MSG_NOSIGNAL);
        if (written > 0) {
            sent += static_cast<size_t>(written);
        } else if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (!wait_socket(fd, POLLOUT, deadline, cancel)) {
                ::close(fd);
                return {};
            }
        } else {
            ::close(fd);
            return {};
        }
    }
    std::string response;
    char buffer[16384];
    while (response.size() < 8 * 1024 * 1024) {
        const ssize_t got = ::recv(fd, buffer, sizeof buffer, 0);
        if (got > 0) {
            response.append(buffer, static_cast<size_t>(got));
        } else if (got == 0) {
            break;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (!wait_socket(fd, POLLIN, deadline, cancel)) {
                ::close(fd);
                return {};
            }
        } else {
            break;
        }
    }
    ::close(fd);
    return parse_docker_response(response);
}

std::string search_text(const Listener& row) {
    return row.protocol + " " + row.address + " " + std::to_string(row.port) + " " + row.process + " " + row.command +
           " " + (row.pid ? std::to_string(*row.pid) : std::string()) + " " + row.user;
}

std::string detail_text(const Listener& row) {
    return row.protocol + " " + row.address + ":" + std::to_string(row.port) + "\n" + "PID：" +
           (row.pid ? std::to_string(*row.pid) : std::string("系统")) + "  用户：" + row.user + "  运行：" + row.age +
           "\n进程：" + row.process + "\n工作目录：" + row.cwd + "\n父 PID：" +
           (row.parent ? std::to_string(*row.parent) : std::string("--")) + "\nDocker：" +
           (row.docker.empty() ? std::string("--") : row.docker) + "\n\n完整命令行：\n" + row.command +
           "\n\n j/k 或 ↑↓ 滚动  PgUp/PgDn 翻页  Esc 返回";
}

const char* sort_label(Sort sort) {
    switch (sort) {
        case Sort::Port: return "端口";
        case Sort::Protocol: return "协议";
        case Sort::Pid: return "PID";
        case Sort::Process: return "进程";
        case Sort::Address: return "地址";
    }
    return "端口";
}

std::vector<size_t> App::visible() const {
    std::vector<size_t> out;
    const std::string query = filter.str();
    if (filter.empty()) {
        out.reserve(rows.size());
        for (size_t i = 0; i < rows.size(); ++i) out.push_back(i);
        return out;
    }
    for (size_t i = 0; i < rows.size(); ++i) {
        if (tui::match(query, search_text(rows[i]))) out.push_back(i);
    }
    return out;
}

const Listener* App::selected_row() const {
    const auto ids = visible();
    if (selected < ids.size()) return &rows[ids[selected]];
    return nullptr;
}

void App::keep_selection(std::optional<SelectionKey> key) {
    const auto ids = visible();
    selected = 0;
    if (key) {
        for (size_t i = 0; i < ids.size(); ++i) {
            if (rows[ids[i]].key() == *key) {
                selected = i;
                break;
            }
        }
    }
    if (!ids.empty()) selected = std::min(selected, ids.size() - 1);
}

void App::merge(std::vector<Listener> next) {
    const Listener* current = selected_row();
    const std::optional<SelectionKey> key = current ? std::optional<SelectionKey>(current->key()) : std::nullopt;
    std::stable_sort(next.begin(), next.end(), [this](const Listener& a, const Listener& b) {
        switch (sort) {
            case Sort::Port: return a.port < b.port;
            case Sort::Protocol: return a.protocol < b.protocol;
            case Sort::Pid: return a.pid < b.pid;
            case Sort::Process: return a.process < b.process;
            case Sort::Address: return a.address < b.address;
        }
        return false;
    });
    rows = std::move(next);
    keep_selection(key);
}

void App::resort() {
    const Listener* current = selected_row();
    const std::optional<SelectionKey> key = current ? std::optional<SelectionKey>(current->key()) : std::nullopt;
    std::stable_sort(rows.begin(), rows.end(), [this](const Listener& a, const Listener& b) {
        switch (sort) {
            case Sort::Port: return a.port < b.port;
            case Sort::Protocol: return a.protocol < b.protocol;
            case Sort::Pid: return a.pid < b.pid;
            case Sort::Process: return a.process < b.process;
            case Sort::Address: return a.address < b.address;
        }
        return false;
    });
    keep_selection(key);
}

void App::move_by(int delta) {
    const size_t length = visible().size();
    if (length == 0) return;
    const long next = static_cast<long>(selected) + delta;
    selected = static_cast<size_t>(std::clamp<long>(next, 0, static_cast<long>(length) - 1));
}

void App::begin_filter() {
    filter_snapshot = FilterSnapshot{
        filter.str(), selected_row() ? std::optional<SelectionKey>(selected_row()->key()) : std::nullopt};
    filtering = true;
}

void App::cancel_filter() {
    if (filter_snapshot) {
        filter.set(filter_snapshot->filter);
        keep_selection(filter_snapshot->key);
    }
    filter_snapshot.reset();
    filtering = false;
}

void App::finish_filter() {
    filtering = false;
    filter_snapshot.reset();
}

void App::filter_changed(std::optional<SelectionKey> selected_key) { keep_selection(selected_key); }

void App::signal() {
    const Listener* current = selected_row();
    if (!current) return;
    const Listener row = *current;
    if (!row.pid) {
        message = "没有可见的属主进程";
        return;
    }
    if (row.uid != std::optional<uint32_t>(static_cast<uint32_t>(::geteuid()))) {
        message = "只允许结束当前用户的进程";
        return;
    }
    if (!row.start_ticks) {
        message = "无法验证进程启动时间";
        return;
    }
    confirm = Confirm{*row.pid, *row.start_ticks, false};
}

void App::send_signal(int32_t pid, uint64_t start, bool hard) {
    const auto own = static_cast<uint32_t>(::geteuid());
    const auto details = proc_details(pid);
    if (!details) {
        message = "进程已退出或不可见";
        return;
    }
    if (!same_process(*details, own, start)) {
        message = "进程身份已变化，已取消信号";
        return;
    }
    const int pidfd = static_cast<int>(::syscall(SYS_pidfd_open, pid, 0));
    if (pidfd < 0) {
        message = "pidfd_open 失败；为避免 PID 重用，没有发送信号";
        return;
    }
    const auto again = proc_details(pid);
    if (!again || !same_process(*again, own, start)) {
        ::close(pidfd);
        message = "pidfd 复核发现进程身份变化，已取消信号";
        return;
    }
    const int number = hard ? SIGKILL : SIGTERM;
    const long rc = ::syscall(SYS_pidfd_send_signal, pidfd, number, nullptr, 0);
    const int code = errno;
    ::close(pidfd);
    if (rc == 0) {
        message = std::string("已发送 SIG") + (hard ? "KILL" : "TERM") + " 给 " + std::to_string(pid);
    } else {
        message = std::string("发送信号失败：") + std::strerror(code) + " (os error " + std::to_string(code) + ")";
    }
}

void App::handle_key(const Key& key) {
    const KeyCode code = key.code;
    if (filtering) {
        if (code == KeyCode::Escape) {
            cancel_filter();
        } else if (code == KeyCode::Enter) {
            finish_filter();
        } else if (code == KeyCode::Up && !key.ctrl && !key.alt) {
            move_by(-1);
        } else if (code == KeyCode::Down && !key.ctrl && !key.alt) {
            move_by(1);
        } else {
            const Listener* current = selected_row();
            const std::optional<SelectionKey> selected_key =
                current ? std::optional<SelectionKey>(current->key()) : std::nullopt;
            if (filter.handle(key)) filter_changed(selected_key);
        }
        return;
    }
    if (code == KeyCode::Char && (key.ctrl || key.alt)) return;
    if (help) {
        if (code == KeyCode::Escape || key.is(U'?')) help = false;
        return;
    }
    if (detail) {
        switch (code) {
            case KeyCode::Escape:
            case KeyCode::Enter:
                detail = false;
                break;
            case KeyCode::Char:
                if (key.is(U'd')) detail = false;
                else if (key.is(U'j')) detail_scroll = static_cast<uint16_t>(detail_scroll + 1);
                else if (key.is(U'k'))
                    detail_scroll = static_cast<uint16_t>(detail_scroll > 0 ? detail_scroll - 1 : 0);
                break;
            case KeyCode::Down: detail_scroll = static_cast<uint16_t>(detail_scroll + 1); break;
            case KeyCode::Up: detail_scroll = static_cast<uint16_t>(detail_scroll > 0 ? detail_scroll - 1 : 0); break;
            case KeyCode::PageDown: detail_scroll = static_cast<uint16_t>(detail_scroll + 20); break;
            case KeyCode::PageUp: detail_scroll = static_cast<uint16_t>(detail_scroll > 8 ? detail_scroll - 8 : 0); break;
            case KeyCode::Home: detail_scroll = 0; break;
            default: break;
        }
        return;
    }
    if (confirm) {
        const Confirm current = *confirm;
        if (code == KeyCode::Escape || key.is(U'n')) {
            confirm.reset();
        } else if (key.is(U'y') || code == KeyCode::Enter) {
            confirm.reset();
            send_signal(current.pid, current.start, current.hard);
        } else if (key.is(U'k') && !current.hard) {
            confirm = Confirm{current.pid, current.start, true};
        }
        return;
    }
    if (key.is(U'q')) {
        // The page handles quitting at the event level, like the Rust toolbox.
    } else if (key.is(U'?')) {
        help = true;
    } else if (key.is(U'/')) {
        begin_filter();
    } else if (key.is(U'j') || code == KeyCode::Down) {
        move_by(1);
    } else if (key.is(U'k') || code == KeyCode::Up) {
        move_by(-1);
    } else if (code == KeyCode::PageUp) {
        move_by(-static_cast<int>(std::max<size_t>(last_table_rows, 1)));
    } else if (code == KeyCode::PageDown) {
        move_by(static_cast<int>(std::max<size_t>(last_table_rows, 1)));
    } else if (key.is(U'g')) {
        selected = 0;
    } else if (key.is(U'G')) {
        selected = visible().empty() ? 0 : visible().size() - 1;
    } else if (key.is(U'd') || code == KeyCode::Enter) {
        detail = true;
        detail_scroll = 0;
    } else if (key.is(U'o')) {
        if (const Listener* row = selected_row()) {
            message = spawn_detached("xdg-open", "http://localhost:" + std::to_string(row->port))
                          ? "已打开 localhost:" + std::to_string(row->port)
                          : "无法启动 xdg-open";
        }
    } else if (key.is(U'c')) {
        if (const Listener* row = selected_row()) {
            message = run_status("wl-copy", std::to_string(row->port)) ? "端口已复制" : "wl-copy 不可用";
        }
    } else if (key.is(U'x')) {
        signal();
    } else if (key.is(U's')) {
        switch (sort) {
            case Sort::Port: sort = Sort::Protocol; break;
            case Sort::Protocol: sort = Sort::Pid; break;
            case Sort::Pid: sort = Sort::Process; break;
            case Sort::Process: sort = Sort::Address; break;
            case Sort::Address: sort = Sort::Port; break;
        }
        resort();
    } else if (code == KeyCode::Escape && !filter.empty()) {
        const Listener* current = selected_row();
        const std::optional<SelectionKey> selected_key =
            current ? std::optional<SelectionKey>(current->key()) : std::nullopt;
        filter.clear();
        keep_selection(selected_key);
    }
}

std::optional<size_t> clicked_visible_row(Rect body, size_t offset, size_t visible_len, size_t table_rows, int x, int y) {
    if (!body.contains(x, y)) return std::nullopt;
    const int data_y = body.y + 2;
    if (y < data_y) return std::nullopt;
    const size_t row = static_cast<size_t>(y - data_y);
    if (row >= table_rows) return std::nullopt;
    const size_t index = offset + row;
    if (index < visible_len) return index;
    return std::nullopt;
}

bool force_docker(const std::vector<std::string>& args) {
    return std::any_of(args.begin(), args.end(), [](const std::string& arg) { return arg == "--docker-map"; });
}

int run_cli(const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    (void)err;
    if (std::any_of(args.begin(), args.end(),
                    [](const std::string& arg) { return arg == "--help" || arg == "-h"; })) {
        out << "mayon-tools ports [--docker-map]\n监听端口；--docker-map 显式请求 Docker 端口映射。\n";
        return 0;
    }
    if (std::any_of(args.begin(), args.end(), [](const std::string& arg) { return arg == "--version"; })) {
        out << "mayon-tools ports 0.2.0\n";
        return 0;
    }
    return -1;
}

namespace {
constexpr int kFooter = 2;

std::vector<tui::Column> columns_for(int width) {
    // Fixed Rust-like columns, with a wider PID so six digit PIDs do not turn into
    // ellipses, and a narrow tier that keeps the address, PID, process and scope.
    const auto fit = [width](int wanted, int other) { return std::max(std::min(wanted, width - other), 4); };
    if (width >= 108) return {{"协议", 8}, {"监听地址", 27}, {"PID", 7, true}, {"进程", fit(22, 81)}, {"用户", 12}, {"时长", 9, true}, {"范围", 10}};
    if (width >= 78) return {{"协议", 5}, {"监听地址", 22}, {"PID", 7, true}, {"进程", fit(16, 65)}, {"用户", 8}, {"时长", 6, true}, {"范围", 9}};
    return {{"协议", 5}, {"监听地址", 19}, {"PID", 7, true}, {"进程", fit(16, 45)}, {"范围", 8}};
}

bool dev_port(uint16_t port) {
    switch (port) {
        case 3000:
        case 5173:
        case 8000:
        case 8080:
        case 8081:
        case 4200:
        case 5000:
        case 9000:
            return true;
        default:
            return false;
    }
}

std::string address_text(const Listener& row) {
    return row.address + ":" + std::to_string(row.port) + (dev_port(row.port) ? " · DEV" : "");
}

std::string process_text(const Listener& row) {
    return row.docker.empty() ? row.process : row.process + " · " + row.docker;
}

std::string row_text(const Listener& row, size_t column, size_t column_count) {
    if (column_count == 7) {
        switch (column) {
            case 0: return row.protocol;
            case 1: return address_text(row);
            case 2: return row.pid ? std::to_string(*row.pid) : std::string("系统");
            case 3: return process_text(row);
            case 4: return row.user;
            case 5: return row.age;
            default: return scope(row.address);
        }
    }
    switch (column) {
        case 0: return row.protocol;
        case 1: return address_text(row);
        case 2: return row.pid ? std::to_string(*row.pid) : std::string("系统");
        case 3: return process_text(row);
        default: return scope(row.address);
    }
}

void draw_query(Screen& screen, Rect row, const tui::TextInput& filter, std::optional<std::pair<int, int>>& cursor) {
    const int start = tui::put(screen, row.x + 1, row.y, "/ ", Style{tui::kBlue}, std::max(row.width - 1, 0));
    const int room = row.x + row.width - start - 1;
    if (room <= 0 || row.y < 0 || row.y >= screen.dimy()) return;
    std::u32string before = tui::decode(filter.before_cursor());
    const std::u32string all = tui::decode(filter.str());
    size_t skip = 0;
    int used = tui::width_of(tui::encode(before));
    while (used >= room && skip < before.size())
        used -= tui::width_of(tui::encode(std::u32string_view(before).substr(skip++, 1)));
    tui::put(screen, start, row.y, tui::encode(std::u32string_view(all).substr(skip)), Style{tui::kBlue}, room);
    cursor = std::make_pair(start + used, row.y);
}

void draw_row(Screen& screen, Rect row, const std::vector<tui::Column>& columns, const Listener& listener, bool selected,
              const std::string& query) {
    const std::optional<uint32_t> bg = selected ? std::optional<uint32_t>(tui::kSelection) : std::nullopt;
    const auto widths = tui::column_widths(columns, std::max(row.width - 2, 0));
    int content = 2;
    for (const int width : widths) content += width + 1;
    content = std::min(content, row.width);
    if (selected) {
        tui::fill(screen, Rect{row.x, row.y, content, 1}, tui::kSelection);
        tui::put(screen, row.x, row.y, "▌", Style{tui::kBlue, tui::kSelection});
    }
    int x = row.x + 2;
    const std::string label = scope(listener.address);
    for (size_t i = 0; i < columns.size(); ++i) {
        const std::string text = row_text(listener, i, columns.size());
        uint32_t color = tui::kFg;
        if (query.empty() && i == 1 && dev_port(listener.port)) color = tui::kBlue;
        if (query.empty() && i + 1 == columns.size())
            color = label == "对外" ? tui::kRed : label == "本机" ? tui::kGreen : tui::kYellow;
        const Style style{color, bg};
        const int room = std::max(widths[i], 0);
        if (query.empty()) {
            if (columns[i].right) tui::put_right(screen, x + room, row.y, tui::clip(text, room), style);
            else tui::put(screen, x, row.y, tui::clip(text, room), style, room);
        } else {
            const std::string shown = tui::clip(text, room);
            const auto matched = tui::match(query, text);
            const std::vector<std::pair<size_t, size_t>> ranges =
                matched ? matched->ranges : std::vector<std::pair<size_t, size_t>>{};
            const int start = columns[i].right ? x + room - tui::width_of(shown) : x;
            tui::put_ranges(screen, start, row.y, shown, ranges, style, room);
        }
        x += room + 1;
    }
}

void draw_table(Screen& screen, App& app, Rect table) {
    const int content_width = std::max(table.width - 1, 0);
    const auto columns = columns_for(content_width);
    const auto ids = app.visible();
    if (!ids.empty()) app.selected = std::min(app.selected, ids.size() - 1);
    const std::string query = app.filter.str();
    const int label_y = table.y;
    if (label_y >= 0 && label_y < screen.dimy()) {
        const int label_end = tui::put(screen, table.x + 1, label_y, "监听", Style{tui::kMuted, {}, false, true});
        std::string count = "  " + std::to_string(ids.size()) + "/" + std::to_string(app.rows.size()) + " 匹配";
        if (!query.empty()) count += " · /" + query;
        tui::put(screen, label_end, label_y, tui::clip(count, std::max(table.width - 3, 0)), Style{tui::kMuted},
                 std::max(table.width - 3, 0));
    }
    if (table.height >= 2)
        tui::draw_table_header(screen, Rect{table.x + 1, table.y + 1, content_width, 1}, columns);
    const size_t capacity = table.height > 2 ? static_cast<size_t>(table.height - 2) : 0;
    const size_t previous_offset = app.last_table_offset;
    app.last_table_offset = 0;
    app.last_table_rows = 0;
    if (ids.empty()) {
        std::string text;
        if (app.message.starts_with("读取监听失败：")) text = app.message;
        else if (query.empty()) text = "没有监听项 · r 刷新 / 检查进程是否监听";
        else text = "没有匹配的监听项 · Esc 清除过滤";
        const auto lines = tui::wrap(text, std::max(table.width - 4, 1), std::max(static_cast<int>(capacity), 1));
        int y = table.y + 2;
        for (const std::string& line : lines) tui::put(screen, table.x + 3, y++, line, Style{tui::kMuted});
        return;
    }
    const size_t offset = tui::scroll_to(app.selected, previous_offset, capacity, ids.size());
    for (size_t i = 0; i < capacity; ++i) {
        const size_t index = offset + i;
        if (index >= ids.size()) break;
        draw_row(screen, Rect{table.x + 1, table.y + 2 + static_cast<int>(i), content_width, 1}, columns,
                 app.rows[ids[index]], index == app.selected, query);
    }
    app.last_table_offset = offset;
    app.last_table_rows = capacity;
}

void draw_detail(Screen& screen, const App& app) {
    const Listener* current = app.selected_row();
    if (!current) return;
    const int width = std::min(screen.dimx() - 2, 88);
    const int height = std::min(screen.dimy() - 2, 40);
    if (width < 10 || height < 4) return;
    const Rect area = tui::centered(screen.dimx(), screen.dimy(), width, height);
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, "监听详情 · j/k 滚动 · Esc 返回", false, tui::kSurface);
    const int room = area.width - 6;
    const auto lines = tui::wrap(detail_text(*current), room, 100000);
    int y = area.y + 1;
    const int bottom = area.y + area.height - 1;
    for (size_t i = app.detail_scroll; i < lines.size() && y < bottom; ++i, ++y)
        tui::put(screen, area.x + 3, y, tui::clip(lines[i], room), Style{tui::kFg, tui::kSurface}, room);
}

void draw_help(Screen& screen) {
    const std::string body =
        "j/k 或 ↑↓ 选择；滚轮滚动。/ 输入过滤；输入中的 ↑↓ 仍可移动选中项，Enter 保留过滤，Esc 取消本次输入。列表 Esc 清除过滤。s "
        "循环按端口/协议/PID/进程/地址排序。d/Enter 查看完整命令、cwd 与父进程。o 打开 localhost:<port>，c 复制端口。x "
        "进入确认；确认中 y 发 SIGTERM，k 再确认后才能发 SIGKILL。系统进程显示为“系统”，不发送信号。\nIPv4/IPv6 TCP 与 UDP 来自 "
        "/proc/net；每 2 秒刷新并按 socket 保留选择。0.0.0.0/:: 标为对外，127/8 与 ::1 标为本机，其他绑定标为指定接口。";
    const int width = std::min(screen.dimx() - 2, 80);
    if (width < 10) return;
    const auto lines = tui::wrap(body, width - 6, 100000);
    const int height = std::min(screen.dimy() - 2, static_cast<int>(lines.size()) + 4);
    const Rect area = tui::centered(screen.dimx(), screen.dimy(), width, height);
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, "帮助 · ? / Esc 关闭", false, tui::kSurface);
    int y = area.y + 1;
    for (const std::string& line : lines) {
        if (y >= area.y + area.height - 1) break;
        tui::put(screen, area.x + 3, y++, tui::clip(line, width - 6), Style{tui::kFg, tui::kSurface}, width - 6);
    }
}

void draw_confirm(Screen& screen, const Confirm& confirm) {
    const std::string title = confirm.hard ? "二次确认 · SIGKILL" : "确认结束进程";
    const std::string body = "PID " + std::to_string(confirm.pid) + "\n" +
                             (confirm.hard ? "发送 SIGKILL，进程将立即终止。"
                                           : "向当前用户的进程发送 SIGTERM。按 k 可进入 SIGKILL 二次确认。") +
                             "\n按 y 确认 · Esc 取消";
    const int width = std::min(screen.dimx() - 2, 80);
    const auto lines = tui::wrap(body, width - 6, 8);
    const int height = std::min(screen.dimy() - 2, static_cast<int>(lines.size()) + 2);
    const Rect area = tui::centered(screen.dimx(), screen.dimy(), width, height);
    tui::fill(screen, area, tui::kSurface);
    tui::box(screen, area, title, false, tui::kSurface);
    int y = area.y + 1;
    for (const std::string& line : lines) {
        if (y >= area.y + area.height - 1) break;
        tui::put(screen, area.x + 3, y++, tui::clip(line, width - 6), Style{tui::kFg, tui::kSurface}, width - 6);
    }
}

}  // namespace

void draw(Screen& screen, App& app, Rect area, std::optional<std::pair<int, int>>* cursor) {
    std::optional<std::pair<int, int>> local_cursor;
    std::optional<std::pair<int, int>>& target = cursor ? *cursor : local_cursor;
    target.reset();
    if (area.width <= 0 || area.height <= 0) return;
    const std::string title = std::string("端口监听  ·  ") + std::to_string(app.visible().size()) + "/" +
                              std::to_string(app.rows.size()) + " 匹配  ·  排序 " + sort_label(app.sort);
    tui::put(screen, area.x + 1, area.y, tui::clip(title, std::max(area.width - 2, 0)), Style{tui::kBrightFg});
    int top = area.y + 1;
    if (top < area.y + area.height) tui::draw_tabs(screen, area.x + 1, top, {"监听"}, 0);
    ++top;
    const int footer_y = area.y + area.height - kFooter;
    Rect table{area.x, top, area.width, std::max(footer_y - top, 0)};
    if (app.filtering && table.height > 0) {
        draw_query(screen, Rect{table.x, table.y, table.width, 1}, app.filter, target);
        table.y += 1;
        table.height = std::max(table.height - 1, 0);
    }
    app.last_body = table;
    draw_table(screen, app, table);
    if (footer_y >= 0 && footer_y < screen.dimy()) {
        tui::put_hints(screen, area.x + 1, footer_y, std::max(area.width - 2, 0),
                       {{"j/k", "选择"},
                        {"/", "过滤"},
                        {"s", "排序"},
                        {"d", "详情"},
                        {"o", "浏览器"},
                        {"c", "复制"},
                        {"x", "确认结束"},
                        {"?", "帮助"},
                        {"q", "退出"}});
        tui::put(screen, area.x + 1, footer_y + 1, tui::clip(app.message, std::max(area.width - 2, 0)),
                 Style{tui::kBlue});
    }
    if (app.help) {
        draw_help(screen);
        target.reset();
    } else if (app.detail) {
        draw_detail(screen, app);
        target.reset();
    } else if (app.confirm) {
        draw_confirm(screen, *app.confirm);
        target.reset();
    }
}

class PortsPage final : public tui::Page {
public:
    explicit PortsPage(const std::vector<std::string>& args) : force_docker_(ports::force_docker(args)) {
        app_.rows = scan_proc();
        last_ = Clock::now();
    }
    ~PortsPage() override { suspend(); }
    void attach(tui::Post post) override { post_ = std::move(post); }
    void set_active(bool active) override {
        if (active == active_) return;
        if (!active) {
            active_ = false;
            suspend();
            return;
        }
        active_ = true;
        cancel_ = false;
        last_ = ever_active_ ? Clock::now() - std::chrono::seconds(3) : Clock::now();
        ever_active_ = true;
    }
    std::optional<tui::TimePoint> next_deadline() const override {
        if (!active_) return std::nullopt;
        auto next = busy_ ? Clock::now() + std::chrono::hours(1) : last_ + std::chrono::seconds(2);
        if (message_until_) next = std::min(next, *message_until_);
        return next;
    }
    void tick() override {
        const auto now = Clock::now();
        if (message_until_ && now >= *message_until_) {
            message_until_.reset();
            app_.message.clear();
        }
        if (!active_ || busy_) return;
        if (now - last_ < std::chrono::seconds(2)) return;
        last_ = now;
        start_refresh();
    }
    bool handle(const InputEvent& event) override {
        const std::string before = app_.message;
        bool quit = false;
        switch (event.type) {
            case InputEvent::Type::Key: {
                const Key& key = event.key;
                if (key.ctrl && key.ch == U'c') return true;
                const bool overlay = app_.help || app_.detail || app_.confirm.has_value() || app_.filtering;
                if (key.is(U'r') && !overlay) last_ = Clock::now() - std::chrono::seconds(3);
                if (key.is(U'q') && !overlay) return true;
                app_.handle_key(key);
                break;
            }
            case InputEvent::Type::Paste: {
                if (app_.filtering && !app_.help && !app_.detail && !app_.confirm) {
                    const Listener* current = app_.selected_row();
                    const std::optional<SelectionKey> selected_key =
                        current ? std::optional<SelectionKey>(current->key()) : std::nullopt;
                    const std::string old = app_.filter.str();
                    app_.filter.paste(event.paste);
                    if (app_.filter.str() != old) app_.filter_changed(selected_key);
                }
                break;
            }
            case InputEvent::Type::MouseClick:
            case InputEvent::Type::WheelUp:
            case InputEvent::Type::WheelDown: {
                if (app_.help || app_.detail || app_.confirm || app_.filtering) break;
                if (event.type == InputEvent::Type::WheelDown) {
                    if (app_.last_body.contains(event.x, event.y)) app_.move_by(3);
                } else if (event.type == InputEvent::Type::WheelUp) {
                    if (app_.last_body.contains(event.x, event.y)) app_.move_by(-3);
                } else if (const auto index =
                               clicked_visible_row(app_.last_body, app_.last_table_offset, app_.visible().size(),
                                                   app_.last_table_rows, event.x, event.y)) {
                    app_.selected = *index;
                }
                break;
            }
            case InputEvent::Type::FocusIn:
            case InputEvent::Type::FocusOut:
                break;
        }
        if (app_.message != before) message_until_ = Clock::now() + std::chrono::seconds(5);
        return quit;
    }
    void draw(Screen& screen, Rect area) override { ports::draw(screen, app_, area, &cursor_); }
    std::optional<std::pair<int, int>> cursor() const override { return cursor_; }
    bool editing() const override { return app_.filtering || app_.confirm.has_value(); }

private:
    void suspend() {
        cancel_ = true;
        ++generation_;
        if (worker_.joinable()) worker_.join();
        busy_ = false;
    }
    void start_refresh() {
        if (worker_.joinable()) worker_.join();
        busy_ = true;
        cancel_ = false;
        const uint64_t generation = generation_.load();
        const bool map = force_docker_;
        worker_ = std::thread([this, generation, map] {
            std::vector<Listener> rows = scan_proc();
            if (map && !cancel_.load()) {
                const DockerBindings names = docker_names(true, &cancel_);
                if (!cancel_.load() && generation == generation_.load()) {
                    for (Listener& row : rows) {
                        const std::string protocol = row.protocol == "UDP" ? "udp" : "tcp";
                        row.docker = docker_for_listener(names, protocol, row.port, row.address);
                    }
                }
            }
            if (cancel_.load() || generation != generation_.load()) return;
            tui::Post post = post_;
            if (!post) return;
            post([this, generation, rows = std::move(rows)]() mutable {
                if (generation != generation_.load()) return;
                busy_ = false;
                app_.merge(std::move(rows));
                if (app_.message.starts_with("读取监听失败：")) app_.message.clear();
            });
        });
    }

    App app_;
    const bool force_docker_;
    tui::TimePoint last_;
    bool active_ = false;
    bool ever_active_ = false;
    bool busy_ = false;
    std::optional<tui::TimePoint> message_until_;
    std::atomic<bool> cancel_{false};
    std::atomic<uint64_t> generation_{0};
    std::thread worker_;
    std::optional<std::pair<int, int>> cursor_;
};

}  // namespace ports

std::unique_ptr<tui::Page> make_ports_page() { return make_ports_page(std::vector<std::string>{}); }
std::unique_ptr<tui::Page> make_ports_page(const std::vector<std::string>& args) {
    return std::make_unique<ports::PortsPage>(args);
}
int ports_cli(int argc, char** argv) {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.emplace_back(argv[i]);
    return ports::run_cli(args, std::cout, std::cerr);
}
