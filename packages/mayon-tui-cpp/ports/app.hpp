// Private: the ports model, its state machine and the command line.
// The page in page.cpp only owns the refresh loop and drawing; tests drive this header.
#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <iosfwd>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "ui/draw.hpp"
#include "ui/input.hpp"
#include "ui/search.hpp"

namespace ports {
using SelectionKey = std::tuple<std::string, uint16_t, std::optional<int32_t>, uint64_t>;

struct Listener {
    std::string protocol;
    std::string address;
    uint16_t port = 0;
    std::optional<int32_t> pid;
    std::string process;
    std::string command;
    std::string user;
    std::string age;
    uint64_t inode = 0;
    std::optional<uint64_t> start_ticks;
    std::optional<uint32_t> uid;
    std::string cwd;
    std::optional<int32_t> parent;
    std::string docker;
    SelectionKey key() const;
};

// /proc/net stores addresses as host-endian 32-bit words, four bytes per group for IPv6.
std::optional<std::string> decode_addr(std::string_view hex, bool ipv6);
struct SocketRow {
    std::string protocol;
    std::string address;
    uint16_t port = 0;
    uint64_t inode = 0;
    bool operator==(const SocketRow&) const = default;
};
// A missing or unreadable file is an error; malformed rows are skipped.
std::optional<std::vector<SocketRow>> socket_rows(const std::filesystem::path& path, const std::string& protocol, bool ipv6);
std::vector<Listener> scan_proc();

struct ProcDetails {
    std::string comm;
    std::string command;
    std::string user;
    std::string cwd;
    std::optional<int32_t> parent;
    uint64_t start = 0;
    uint32_t uid = 0;
};
std::optional<ProcDetails> proc_details(int32_t pid);
bool same_process(const ProcDetails& details, uint32_t uid, uint64_t start);
std::string boot_age(uint64_t start_ticks);

std::string scope(const std::string& address);

struct Ip {
    bool v6 = false;
    std::array<uint8_t, 16> bytes{};
    bool unspecified() const;
    bool loopback() const;
    bool operator==(const Ip&) const = default;
};
std::optional<Ip> parse_ip(std::string_view text);

using PortKey = std::pair<std::string, uint16_t>;
struct DockerBindings {
    std::map<PortKey, std::vector<std::pair<std::optional<Ip>, std::string>>> entries;
};
// The exact Rust rule: an explicit DOCKER_HOST, or the demand-activated private marker.
std::optional<std::filesystem::path> docker_socket_path(std::optional<std::string> docker_host,
                                                        std::optional<std::filesystem::path> runtime, bool force);
std::string docker_for_listener(const DockerBindings& bindings, const std::string& protocol, uint16_t port,
                                const std::string& address);
DockerBindings parse_docker_response(std::string_view response);
// Blocking by design; only the worker thread calls this, with a one second budget.
DockerBindings docker_names(bool force, const std::atomic<bool>* cancel = nullptr);

std::string detail_text(const Listener& row);
std::string search_text(const Listener& row);

enum class Sort { Port, Protocol, Pid, Process, Address };
const char* sort_label(Sort sort);

struct Confirm {
    int32_t pid = 0;
    uint64_t start = 0;
    bool hard = false;
    bool operator==(const Confirm&) const = default;
};
struct FilterSnapshot {
    std::string filter;
    std::optional<SelectionKey> key;
};

struct App {
    std::vector<Listener> rows;
    size_t selected = 0;
    tui::TextInput filter;
    bool filtering = false;
    std::optional<FilterSnapshot> filter_snapshot;
    Sort sort = Sort::Port;
    std::string message;
    bool help = false;
    bool detail = false;
    std::optional<Confirm> confirm;
    uint16_t detail_scroll = 0;
    tui::Rect last_body;
    size_t last_table_offset = 0;
    size_t last_table_rows = 0;

    std::vector<size_t> visible() const;
    const Listener* selected_row() const;
    void keep_selection(std::optional<SelectionKey> key);
    void merge(std::vector<Listener> rows);
    void resort();
    void move_by(int delta);
    void begin_filter();
    void cancel_filter();
    void finish_filter();
    void filter_changed(std::optional<SelectionKey> selected);
    void signal();
    void send_signal(int32_t pid, uint64_t start, bool hard);
    void handle_key(const tui::Key& key);
};

std::optional<size_t> clicked_visible_row(tui::Rect body, size_t offset, size_t visible_len, size_t table_rows, int x,
                                          int y);

// The shared renderer. `cursor` receives the filter input position when non-null.
void draw(ftxui::Screen& screen, App& app, tui::Rect area, std::optional<std::pair<int, int>>* cursor);

// Returns 0 when help/version printed, -1 when the caller should open the page.
int run_cli(const std::vector<std::string>& args, std::ostream& out, std::ostream& err);
bool force_docker(const std::vector<std::string>& args);

}  // namespace ports
