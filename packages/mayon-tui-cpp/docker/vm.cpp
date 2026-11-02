#include "vm.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <csignal>
#include <filesystem>
#include <format>
#include <future>
#include <iterator>
#include <map>
#include <memory>
#include <stdexcept>
#include <thread>

#include "api.hpp"
#include "cleanup.hpp"
#include "ui/text.hpp"

extern char** environ;

namespace dock::vm {
namespace {
using Clock = std::chrono::steady_clock;
constexpr size_t kMaxOutput = 4 * 1024 * 1024;
// Thrown when the connection budget ends; never handled as an ordinary query failure.
struct OverBudget {};
void check(const Budget& budget) {
    if ((budget.cancel && budget.cancel->load()) || Clock::now() >= budget.deadline) throw OverBudget{};
}
std::string lowercase(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c + 32) : static_cast<char>(c); });
    return text;
}
struct Fds {
    int fd[2] = {-1, -1};
    ~Fds() {
        for (const int value : fd) {
            if (value >= 0) ::close(value);
        }
    }
    void close(int index) {
        if (fd[index] >= 0) ::close(fd[index]);
        fd[index] = -1;
    }
};
std::vector<char*> c_args(std::vector<std::string>& args) {
    std::vector<char*> out;
    for (std::string& arg : args) out.push_back(arg.data());
    out.push_back(nullptr);
    return out;
}
// The page ignores SIGPIPE; children start with the default again.
struct Attr {
    posix_spawnattr_t value;
    Attr() {
        posix_spawnattr_init(&value);
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, SIGPIPE);
        posix_spawnattr_setsigdefault(&value, &set);
        posix_spawnattr_setflags(&value, POSIX_SPAWN_SETSIGDEF);
    }
    ~Attr() { posix_spawnattr_destroy(&value); }
    Attr(const Attr&) = delete;
    Attr& operator=(const Attr&) = delete;
};
void reap_killed(pid_t pid) {
    ::kill(pid, SIGKILL);
    int status = 0;
    ::waitpid(pid, &status, 0);
}
std::expected<std::string, std::string> query(const Budget& budget, const std::string& uri, const std::string& operation, const std::vector<std::string>& extra) {
    // There is no generic libvirt command entry point and no write connection.
    static const std::set<std::string> allowed{"list", "domstate", "dumpxml", "snapshot-list", "snapshot-dumpxml", "pool-list", "pool-dumpxml", "vol-list", "vol-path"};
    if (std::none_of(kUris.begin(), kUris.end(), [&](const char* known) { return uri == known; }) || !allowed.contains(operation)) return std::unexpected("只读查询白名单拒绝请求");
    check(budget);
    Fds out, err;
    if (::pipe2(out.fd, O_CLOEXEC) != 0 || ::pipe2(err.fd, O_CLOEXEC) != 0) return std::unexpected("无法启动 virsh 只读查询");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, out.fd[1], 1);
    posix_spawn_file_actions_adddup2(&actions, err.fd[1], 2);
    std::vector<std::string> args{"virsh", "--readonly", "--connect", uri, operation};
    args.insert(args.end(), extra.begin(), extra.end());
    auto argv = c_args(args);
    std::vector<std::string> env_text{"LC_ALL=C"};
    for (char** entry = environ; entry && *entry; ++entry) {
        if (!std::string_view(*entry).starts_with("LC_ALL=")) env_text.emplace_back(*entry);
    }
    auto envp = c_args(env_text);
    Attr attr;
    pid_t pid = -1;
    const int spawned = posix_spawnp(&pid, "virsh", &actions, &attr.value, argv.data(), envp.data());
    posix_spawn_file_actions_destroy(&actions);
    if (spawned != 0) return std::unexpected(spawned == ENOENT ? "virsh 未安装；VM 查询不可用" : "无法启动 virsh 只读查询");
    out.close(1);
    err.close(1);
    const auto limit = Clock::now() + std::chrono::seconds(3);
    std::string stdout_text, stderr_text;
    while (out.fd[0] >= 0 || err.fd[0] >= 0) {
        try {
            check(budget);
        } catch (const OverBudget&) {
            reap_killed(pid);
            throw;
        }
        if (Clock::now() >= limit) {
            reap_killed(pid);
            return std::unexpected("libvirt 只读查询超时");
        }
        pollfd fds[2]{{out.fd[0], POLLIN, 0}, {err.fd[0], POLLIN, 0}};
        const int ready = ::poll(fds, 2, 100);
        if (ready < 0 && errno != EINTR) break;
        if (ready <= 0) continue;
        char buffer[65536];
        for (int i = 0; i < 2; ++i) {
            if (fds[i].fd < 0 || !(fds[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
            const ssize_t got = ::read(fds[i].fd, buffer, sizeof buffer);
            if (got > 0) {
                std::string& sink = i == 0 ? stdout_text : stderr_text;
                if (i == 0 || sink.size() < 65536) sink.append(buffer, static_cast<size_t>(got));
            } else if (got == 0 || errno != EINTR) {
                (i == 0 ? out : err).close(0);
            }
        }
        if (stdout_text.size() > kMaxOutput) {
            reap_killed(pid);
            return std::unexpected("libvirt 元数据过大；未继续扫描");
        }
    }
    int status = 0;
    while (::waitpid(pid, &status, WNOHANG) == 0) {
        if (Clock::now() >= limit) {
            reap_killed(pid);
            return std::unexpected("libvirt 只读查询超时");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        const std::string error = lowercase(stderr_text);
        for (const char* word : {"permission", "not authorized", "authentication", "access denied"}) {
            if (error.find(word) != std::string::npos) return std::unexpected("无权限访问 libvirt；未提权");
        }
        return std::unexpected(operation + " 不可用（未启用、连接失败或功能不支持）");
    }
    if (!valid_utf8(stdout_text)) return std::unexpected("libvirt 元数据不是 UTF-8");
    return stdout_text;
}
std::expected<xml::Node, std::string> query_xml(const Budget& budget, const std::string& uri, const std::string& operation, const std::vector<std::string>& extra) {
    const auto text = query(budget, uri, operation, extra);
    if (!text) return std::unexpected(text.error());
    return xml::parse(*text);
}
std::expected<std::optional<std::string>, std::string> source_path(const Budget& budget, const std::string& uri, const xml::Node& node) {
    if (const auto* file = node.attr("file")) return std::optional<std::string>(*file);
    const auto* pool = node.attr("pool");
    const auto* volume = node.attr("volume");
    if (pool && volume) {
        const auto path = query(budget, uri, "vol-path", {"--pool", *pool, "--vol", *volume});
        if (!path) return std::unexpected(path.error());
        return std::optional<std::string>(tui::trim(*path));
    }
    return std::optional<std::string>();
}
bool driver_is_raw(const xml::Node& disk) {
    const xml::Node* driver = disk.child("driver");
    const std::string* type = driver ? driver->attr("type") : nullptr;
    return type && *type == "raw";
}
bool backing_complete(const xml::Node& disk) {
    if (driver_is_raw(disk)) return true;
    const xml::Node* node = disk.child("backingStore");
    if (!node) return false;
    while (true) {
        if (!node->child("source") && !node->child("backingStore")) return true;
        node = node->child("backingStore");
        if (!node) return false;
    }
}
std::optional<uint64_t> file_length(const std::string& path) {
    struct stat info {};
    if (::stat(path.c_str(), &info) != 0 || !S_ISREG(info.st_mode)) return std::nullopt;
    return static_cast<uint64_t>(info.st_size);
}
void snapshots(Census& c, const Budget& budget, const std::string& uri, const std::string& owner, const std::string& uuid) {
    const auto list = query(budget, uri, "snapshot-list", {"--domain", uuid, "--name"});
    if (!list) {
        c.warnings.insert(list.error());
        return;
    }
    const auto lines = split_lines(*list);
    size_t taken = 0;
    for (const std::string& name : lines) {
        if (tui::trim(name).empty()) continue;
        if (taken++ == 128) break;
        const std::string label = owner + " / " + name;
        c.rows.push_back(metadata_row(uri, label, "快照", std::nullopt, std::nullopt, "快照元数据；内部快照已包含在镜像中，不能单独计量"));
        const auto root = query_xml(budget, uri, "snapshot-dumpxml", {"--domain", uuid, "--snapshotname", name});
        if (!root) {
            c.warnings.insert(root.error());
            continue;
        }
        for (const xml::Node* disk : root->descendants("disk")) {
            const xml::Node* source = disk->child("source");
            const std::string* file = source ? source->attr("file") : nullptr;
            const bool local = source && (file || source->attr("pool"));
            const std::string* device = disk->attr("device");
            const bool iso = (device && *device == "cdrom") || (file && image_kind(*file) == "ISO");
            if (local && !iso && !backing_complete(*disk)) c.warnings.insert("快照 backing 链未明确终止；未引用镜像只能待核实");
        }
        // Snapshot domain XML includes older disks and backing chains too.
        for (const xml::Node* source : root->descendants("source")) {
            const auto path = source_path(budget, uri, *source);
            if (!path) c.warnings.insert(path.error());
            else if (*path) c.file(uri, label, "快照磁盘", **path, std::nullopt, "快照引用（保留）");
        }
        if (const xml::Node* memory = root->child("memory")) {
            if (const auto* file_attr = memory->attr("file")) c.file(uri, label, "快照内存", *file_attr, std::nullopt, "外部快照内存（保留）");
        }
    }
    if (lines.size() > 128) c.warnings.insert("快照列表超过128项，统计不完整");
}
void pools(Census& c, const Budget& budget, const std::string& uri) {
    const auto list = query(budget, uri, "pool-list", {"--all", "--name"});
    if (!list) {
        c.warnings.insert(list.error());
        return;
    }
    const auto lines = split_lines(*list);
    size_t taken = 0;
    for (const std::string& pool : lines) {
        if (tui::trim(pool).empty()) continue;
        if (taken++ == 128) break;
        const auto root = query_xml(budget, uri, "pool-dumpxml", {"--pool", pool});
        if (root) {
            const std::string* type = root->attr("type");
            if (type && (*type == "dir" || *type == "fs" || *type == "netfs")) {
                const xml::Node* target = root->child("target");
                const xml::Node* path = target ? target->child("path") : nullptr;
                if (path) {
                    const std::string p = tui::trim(path->text);
                    if (p.starts_with('/')) c.dirs.insert(p);
                }
            }
        } else {
            c.warnings.insert(root.error());
        }
        const auto volumes = query(budget, uri, "vol-list", {"--pool", pool});
        if (!volumes) {
            c.warnings.insert(volumes.error());
            continue;
        }
        const auto names = volume_paths(*volumes);
        if (!names) {
            c.warnings.insert("存储卷列表格式未知，统计不完整");
            continue;
        }
        for (size_t i = 0; i < names->size() && i < 512; ++i) {
            const auto path = query(budget, uri, "vol-path", {"--pool", pool, "--vol", (*names)[i]});
            if (!path) {
                c.warnings.insert(path.error());
                continue;
            }
            const std::string p = tui::trim(*path);
            if (!p.starts_with('/')) {
                c.warnings.insert("存储卷路径不是本地绝对路径");
                continue;
            }
            const std::optional<uint64_t> capacity = image_kind(p) == "ISO" ? file_length(p) : std::nullopt;
            c.volumes.push_back(metadata_row(uri, pool, "存储卷", canonical(p), capacity, "libvirt 池登记；虚拟容量未知时禁止探测镜像头"));
        }
        if (split_lines(*volumes).size() > 514) c.warnings.insert("池卷超过512项，统计不完整");
    }
    if (lines.size() > 128) c.warnings.insert("存储池超过128项，统计不完整");
}
void scan(Census& c, const Budget& budget, const std::string& uri) {
    std::vector<std::pair<std::string, int>> todo;
    for (const std::string& dir : c.dirs) todo.emplace_back(dir, 0);
    size_t count = 0;
    while (!todo.empty()) {
        const auto [dir, depth] = std::move(todo.back());
        todo.pop_back();
        check(budget);
        DIR* handle = ::opendir(dir.c_str());
        if (!handle) {
            c.warnings.insert("存储池目录无权限或不可读，扫描不完整");
            continue;
        }
        const std::unique_ptr<DIR, int (*)(DIR*)> guard(handle, ::closedir);
        while (const dirent* entry = ::readdir(handle)) {
            const std::string_view name = entry->d_name;
            if (name == "." || name == "..") continue;
            if (++count > 10000) {
                c.warnings.insert("存储池扫描超过10000项，统计不完整");
                return;
            }
            const std::string path = dir + (dir.ends_with('/') ? "" : "/") + std::string(name);
            struct stat info {};
            if (::lstat(path.c_str(), &info) != 0) {
                c.warnings.insert("目录项类型未知");
                continue;
            }
            if (S_ISDIR(info.st_mode)) {
                if (depth < 4) todo.emplace_back(path, depth + 1);
                else c.warnings.insert("存储池扫描深度超过4层，统计不完整");
                continue;
            }
            // Directory symlinks are not traversed. File aliases deduplicate by inode.
            if ((S_ISREG(info.st_mode) || S_ISLNK(info.st_mode)) && image_kind(path)) {
                c.volumes.push_back(metadata_row(uri, "存储池目录", "扫描文件", canonical(path), std::nullopt, "仅按扩展名识别；stat，不读取镜像内容"));
            }
        }
    }
}
std::pair<Census, Connection> connection(const Budget& budget, const std::string& uri) {
    Census c;
    const auto list = query(budget, uri, "list", {"--all", "--uuid"});
    if (!list) return {std::move(c), Connection{uri, list.error(), false}};
    const auto lines = split_lines(*list);
    size_t taken = 0;
    for (const std::string& line : lines) {
        const std::string uuid = tui::trim(line);
        if (uuid.empty()) continue;
        if (taken++ == 128) break;
        if (!std::all_of(uuid.begin(), uuid.end(), [](unsigned char b) { return std::isxdigit(b) != 0 || b == '-'; })) {
            c.warnings.insert("VM UUID 非法，未查询");
            continue;
        }
        const auto state = query(budget, uri, "domstate", {"--domain", uuid});
        const auto xml_now = query_xml(budget, uri, "dumpxml", {"--domain", uuid});
        std::string owner = uuid;
        if (xml_now) {
            if (const xml::Node* name = xml_now->child("name")) owner = name->text;
        }
        c.rows.push_back(metadata_row(uri, owner, "虚拟机", std::nullopt, std::nullopt, tui::trim(state ? *state : "状态未知")));
        if (xml_now) domain_disks(c, budget, uri, owner, *xml_now, true);
        else c.warnings.insert(xml_now.error());
        const auto inactive = query_xml(budget, uri, "dumpxml", {"--domain", uuid, "--inactive"});
        if (inactive) domain_disks(c, budget, uri, owner, *inactive, false);
        else c.warnings.insert(inactive.error());
        snapshots(c, budget, uri, owner, uuid);
    }
    if (lines.size() > 128) c.warnings.insert("VM 超过128项，统计不完整");
    pools(c, budget, uri);
    scan(c, budget, uri);
    const bool complete = c.warnings.empty();
    std::string status = "只读连接可用";
    if (!complete) {
        status = "部分可用：";
        bool first = true;
        for (const std::string& warning : c.warnings) {
            if (!first) status += "；";
            status += warning;
            first = false;
        }
    }
    return {std::move(c), Connection{uri, std::move(status), complete}};
}
std::pair<Census, Connection> bounded_connection(const std::string& uri, const tui::Cancel& cancel) {
    try {
        return connection(Budget{cancel, Clock::now() + std::chrono::seconds(30)}, uri);
    } catch (const OverBudget&) {
        return {Census{}, Connection{uri, "只读查询超过30秒；本连接统计不可用", false}};
    }
}
std::string path_text(const std::optional<std::string>& path) { return path ? *path : "—"; }
}  // namespace

std::string Row::key() const { return std::format("{}:{}:{}:{}", uri, owner, kind, path ? "Some(\"" + *path + "\")" : "None"); }
std::string Row::details() const {
    return std::format("{} · {}\n{}\n路径：{}\n占用 {} · 虚拟 {}\n{}\n\nVM 严格只读：不可选、不可清理。\ny 复制完整路径 · Esc 返回", kind, owner, uri, path_text(path), cleanup::bytes(actual), cleanup::bytes(virtual_size), note);
}
Inventory Inventory::pending() {
    Inventory out;
    for (const char* uri : kUris) out.connections.push_back(Connection{uri, "等待只读查询", false});
    return out;
}
std::string Inventory::summary() const {
    struct Sizes {
        std::optional<uint64_t> allocated, capacity;
        bool disk = false;
    };
    std::map<std::string, Sizes> files;
    for (const Row& row : rows) {
        if (!row.path) continue;
        const std::string identity = row.identity ? std::format("inode:{}:{}", row.identity->first, row.identity->second) : "path:" + *row.path;
        Sizes& sizes = files[identity];
        sizes.allocated = std::max(sizes.allocated, row.actual);
        if (row.kind != "ISO" && row.kind != "快照内存") {
            sizes.disk = true;
            sizes.capacity = std::max(sizes.capacity, row.virtual_size);
        }
    }
    uint64_t actual = 0, capacity = 0;
    size_t unknown = 0, virtual_unknown = 0;
    const auto add = [](uint64_t a, uint64_t b) { return a > UINT64_MAX - b ? UINT64_MAX : a + b; };
    for (const auto& [identity, sizes] : files) {
        if (sizes.disk && !sizes.capacity) ++virtual_unknown;
        if (sizes.allocated) actual = add(actual, *sizes.allocated);
        else ++unknown;
        capacity = add(capacity, sizes.capacity.value_or(0));
    }
    const bool incomplete = std::any_of(connections.begin(), connections.end(), [](const Connection& c) { return !c.complete; });
    return std::format("VM：已知占用 {} · 已知虚拟 {}{}{}", cleanup::bytes(actual), virtual_unknown > 0 ? std::format("{} + {}项未知", cleanup::bytes(capacity), virtual_unknown) : cleanup::bytes(capacity),
                       unknown > 0 ? std::format(" · {} 项大小未知", unknown) : "", incomplete ? " · 统计不完整" : " · 文件去重");
}
std::string Inventory::cli() const {
    std::string out = "VM 空间（严格只读）\n" + summary();
    for (const Connection& c : connections) out += std::format("\n{}：{}", c.uri, c.status);
    for (const Row& r : rows) out += std::format("\n{} · {} · {}\n路径：{}\n占用 {} · 虚拟 {}\n{}", r.uri, r.owner, r.kind, path_text(r.path), cleanup::bytes(r.actual), cleanup::bytes(r.virtual_size), r.note);
    return out;
}
void Census::file(const std::string& uri, const std::string& owner, const std::string& kind, const std::string& path, std::optional<uint64_t> capacity, const std::string& note) {
    if (!path.starts_with('/')) {
        warnings.insert("相对路径无法安全定位，未扫描");
        return;
    }
    const std::string real = canonical(path);
    refs.insert(real);
    rows.push_back(metadata_row(uri, owner, kind, real, capacity, note));
}
std::string canonical(const std::string& path) {
    std::error_code error;
    const auto real = std::filesystem::canonical(path, error);
    return error ? path : real.string();
}
Row metadata_row(const std::string& uri, const std::string& owner, const std::string& kind, std::optional<std::string> path, std::optional<uint64_t> virtual_size, const std::string& note) {
    Row row;
    row.uri = uri;
    row.owner = owner;
    row.kind = kind;
    row.virtual_size = virtual_size;
    row.note = note;
    if (path) {
        struct stat info {};
        if (::stat(path->c_str(), &info) == 0 && S_ISREG(info.st_mode)) {
            row.actual = static_cast<uint64_t>(info.st_blocks) * 512;
            row.identity = std::pair<uint64_t, uint64_t>(info.st_dev, info.st_ino);
        } else {
            row.note = note + "；文件缺失、非普通文件或无 stat 权限，大小未知";
        }
    }
    row.path = std::move(path);
    return row;
}
std::expected<std::vector<std::string>, std::string> volume_paths(std::string_view table) {
    std::vector<std::string> paths;
    for (const std::string& raw : split_lines(table)) {
        const std::string line = tui::trim(raw);
        if (line.empty() || line.starts_with("Name") || line.find_first_not_of('-') == std::string::npos) continue;
        // File volume paths are absolute; spaces within the path are kept.
        const size_t split = line.find(" /");
        if (split == std::string::npos) return std::unexpected("volume path unavailable");
        paths.push_back(line.substr(split + 1));
    }
    return paths;
}
std::optional<std::string> image_kind(const std::string& path) {
    std::string extension = std::filesystem::path(path).extension().string();
    if (extension.empty() || !valid_utf8(extension)) return std::nullopt;
    extension = lowercase(extension.substr(1));
    if (extension == "iso") return "ISO";
    for (const char* known : {"qcow", "qcow2", "img", "raw", "vmdk", "vdi", "vhd", "vhdx"}) {
        if (extension == known) return "镜像";
    }
    return std::nullopt;
}
void domain_disks(Census& c, const Budget& budget, const std::string& uri, const std::string& owner, const xml::Node& root, bool live) {
    const xml::Node* devices = root.child("devices");
    if (!devices) return;
    for (const xml::Node& disk : devices->children) {
        if (disk.name != "disk") continue;
        const std::string* device = disk.attr("device");
        const bool is_iso = device && *device == "cdrom";
        const std::string kind = is_iso ? "ISO" : "磁盘";
        if (!is_iso && !backing_complete(disk)) c.warnings.insert("backing 链未明确终止；未引用镜像只能待核实");
        const xml::Node* direct = disk.child("source");
        if (direct) {
            const auto path = source_path(budget, uri, *direct);
            if (!path) {
                c.warnings.insert(path.error());
            } else if (*path) {
                // Only raw / ISO logical length is knowable without probing headers.
                const bool plain = is_iso || (driver_is_raw(disk) && disk.descendants("encryption").empty() && disk.descendants("slices").empty());
                const std::optional<uint64_t> capacity = plain ? file_length(**path) : std::nullopt;
                c.file(uri, owner, kind, **path, capacity, !live ? "持久 VM 配置引用；只读保留" : plain ? "当前 VM 引用；raw / ISO 虚拟大小取文件逻辑长度" : "当前 VM 引用；qcow2 虚拟大小未知：禁止读取镜像头");
            } else if (direct->attr("protocol") || direct->attr("dev")) {
                c.rows.push_back(metadata_row(uri, owner, "远程/块盘", std::nullopt, std::nullopt, "非本地普通镜像；不读取内容，不计本地占用"));
            }
        }
        // Backing chains, dataStore and active mirrors are references too.
        for (const xml::Node* source : disk.descendants("source")) {
            if (source == direct) continue;
            const auto path = source_path(budget, uri, *source);
            if (!path) c.warnings.insert(path.error());
            else if (*path) c.file(uri, owner, "依赖", **path, std::nullopt, "backing / dataStore / mirror 引用");
        }
        for (const xml::Node* mirror : disk.descendants("mirror")) {
            if (const auto* file_attr = mirror->attr("file")) c.file(uri, owner, "依赖", *file_attr, std::nullopt, "活动 mirror 引用");
        }
    }
}
Inventory merge(std::vector<std::pair<Census, Connection>> parts) {
    const bool all_complete = std::all_of(parts.begin(), parts.end(), [](const auto& part) { return part.second.complete; });
    std::set<std::string> refs;
    std::set<std::pair<uint64_t, uint64_t>> referenced_ids;
    for (const auto& part : parts) {
        refs.insert(part.first.refs.begin(), part.first.refs.end());
        for (const Row& row : part.first.rows) {
            if (row.identity) referenced_ids.insert(*row.identity);
        }
    }
    Inventory result;
    std::vector<Row> volumes;
    for (auto& part : parts) {
        result.connections.push_back(std::move(part.second));
        std::move(part.first.rows.begin(), part.first.rows.end(), std::back_inserter(result.rows));
        std::move(part.first.volumes.begin(), part.first.volumes.end(), std::back_inserter(volumes));
    }
    // Sizes known from stat (ISO/raw) win over extension-only scan rows.
    std::stable_sort(volumes.begin(), volumes.end(), [](const Row& a, const Row& b) { return a.virtual_size.has_value() && !b.virtual_size.has_value(); });
    std::set<std::pair<std::string, std::string>> known;
    for (const Row& row : result.rows) {
        if (row.path) known.emplace(row.uri, *row.path);
    }
    for (Row& volume : volumes) {
        if (!volume.path) continue;
        const std::string path = *volume.path;
        for (Row& row : result.rows) {
            if (row.path == path && !row.virtual_size) row.virtual_size = volume.virtual_size;
        }
        if (!known.emplace(volume.uri, path).second) continue;
        const auto kind = image_kind(path);
        if (kind == "ISO") {
            volume.kind = "ISO";
            volume.note = refs.contains(path) ? "已知 VM 引用的 ISO；只显示/复制，不删除" : "未见已知 VM 引用的 ISO；只显示/复制，不删除";
        } else if (refs.contains(path) || (volume.identity && referenced_ids.contains(*volume.identity))) {
            volume.kind = "依赖";
            volume.note = "另一个 VM/快照/连接的引用，保留";
        } else if (kind == "镜像") {
            volume.kind = all_complete ? "孤立镜像候选" : "未引用待核实";
            volume.note = "仅已列 VM/快照/已知 backing 链的引用；绝不删除";
        } else {
            volume.kind = "存储卷";
        }
        result.rows.push_back(std::move(volume));
    }
    std::set<std::string> seen;
    std::erase_if(result.rows, [&](const Row& row) { return !seen.insert(row.key()).second; });
    std::stable_sort(result.rows.begin(), result.rows.end(), [](const Row& a, const Row& b) {
        if (a.actual != b.actual) return a.actual > b.actual;
        return a.key() < b.key();
    });
    for (const Connection& c : result.connections) result.rows.push_back(metadata_row(c.uri, "连接状态", "连接", std::nullopt, std::nullopt, c.status));
    return result;
}
Inventory collect(tui::Cancel cancel) {
    auto session = std::async(std::launch::async, [&] { return bounded_connection(kUris[0], cancel); });
    auto system = bounded_connection(kUris[1], cancel);
    std::vector<std::pair<Census, Connection>> parts;
    parts.push_back(session.get());
    parts.push_back(std::move(system));
    return merge(std::move(parts));
}
void copy_path(const std::string& path) {
    // Only the path is passed; no shell, file open, VM mutation, or file manager.
    Fds in;
    if (::pipe2(in.fd, O_CLOEXEC) != 0) throw std::runtime_error("无法复制路径");
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, in.fd[0], 0);
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0);
    std::vector<std::string> args{"wl-copy", "--type", "text/plain"};
    auto argv = c_args(args);
    Attr attr;
    pid_t pid = -1;
    const int spawned = posix_spawnp(&pid, "wl-copy", &actions, &attr.value, argv.data(), environ);
    posix_spawn_file_actions_destroy(&actions);
    if (spawned != 0) throw std::runtime_error("wl-copy 不可用；完整路径见详情");
    in.close(0);
    std::string_view rest = path;
    while (!rest.empty()) {
        const ssize_t wrote = ::write(in.fd[1], rest.data(), rest.size());
        if (wrote < 0) {
            if (errno == EINTR) continue;
            reap_killed(pid);
            throw std::runtime_error("无法写入剪贴板");
        }
        rest.remove_prefix(static_cast<size_t>(wrote));
    }
    in.close(1);
    const auto limit = Clock::now() + std::chrono::seconds(3);
    int status = 0;
    while (::waitpid(pid, &status, WNOHANG) == 0) {
        if (Clock::now() >= limit) {
            reap_killed(pid);
            throw std::runtime_error("复制路径超时");
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) throw std::runtime_error("剪贴板不可用；完整路径见详情");
}
}  // namespace dock::vm
