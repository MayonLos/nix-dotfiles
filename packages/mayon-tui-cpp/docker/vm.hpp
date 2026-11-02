// Strictly read-only libvirt metadata inventory. Image files are never opened. Private to this tool.
#pragma once
#include <array>
#include <chrono>
#include <cstdint>
#include <expected>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "ui/http.hpp"
#include "vm_xml.hpp"

namespace dock::vm {
inline constexpr std::array<const char*, 2> kUris{"qemu:///session", "qemu:///system"};
struct Row {
    std::string uri, owner, kind;
    std::optional<std::string> path;
    std::optional<uint64_t> actual, virtual_size;
    std::string note;
    std::optional<std::pair<uint64_t, uint64_t>> identity;
    std::string key() const;
    std::string details() const;
};
struct Connection {
    std::string uri, status;
    bool complete = false;
};
struct Inventory {
    std::vector<Row> rows;
    std::vector<Connection> connections;
    static Inventory pending();
    std::string summary() const;
    std::string cli() const;
};
struct Census {
    std::vector<Row> rows;
    std::set<std::string> refs, dirs;
    std::vector<Row> volumes;
    std::set<std::string> warnings;
    void file(const std::string& uri, const std::string& owner, const std::string& kind, const std::string& path, std::optional<uint64_t> capacity, const std::string& note);
};
// Bounds one connection's whole collection; passing it ends that connection's scan.
struct Budget {
    tui::Cancel cancel;
    std::chrono::steady_clock::time_point deadline;
};
std::string canonical(const std::string& path);
Row metadata_row(const std::string& uri, const std::string& owner, const std::string& kind, std::optional<std::string> path, std::optional<uint64_t> virtual_size, const std::string& note);
std::expected<std::vector<std::string>, std::string> volume_paths(std::string_view table);
std::optional<std::string> image_kind(const std::string& path);
void domain_disks(Census& census, const Budget& budget, const std::string& uri, const std::string& owner, const xml::Node& root, bool live);
Inventory merge(std::vector<std::pair<Census, Connection>> parts);
// The only entry point that runs virsh; its fixed operation allowlist is inside.
Inventory collect(tui::Cancel cancel = nullptr);
// Throws std::runtime_error with the user message. Only the path is passed.
void copy_path(const std::string& path);
}  // namespace dock::vm
