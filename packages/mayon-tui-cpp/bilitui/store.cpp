#include "store.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>

#include "core/model.hpp"
#include "ui/text.hpp"

namespace fs = std::filesystem;
namespace bili {
static fs::path home() {
    const char* value = std::getenv("HOME");
    return value ? fs::path(value) : fs::path(".");
}
static fs::path xdg(const char* key, const char* fallback) {
    const char* value = std::getenv(key);
    return value && *value ? fs::path(value) : home() / fallback;
}
fs::path data_dir() { return xdg("XDG_DATA_HOME", ".local/share") / "bilitui"; }
fs::path cache_dir() { return xdg("XDG_CACHE_HOME", ".cache") / "bilitui"; }
void private_dir(const fs::path& path) {
    fs::create_directories(path);
    if (fs::is_symlink(fs::symlink_status(path))) throw std::runtime_error("私有目录不可为符号链接");
    fs::permissions(path, fs::perms::owner_all, fs::perm_options::replace);
}
void write_private(const fs::path& path, const std::string& bytes) {
    private_dir(path.parent_path());
    const fs::path temp = path.string() + ".tmp-" + std::to_string(getpid());
    const int fd = ::open(temp.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) throw std::runtime_error("无法写入私有文件");
    size_t written = 0;
    bool ok = true;
    while (written < bytes.size() && ok) {
        const ssize_t n = ::write(fd, bytes.data() + written, bytes.size() - written);
        ok = n > 0;
        if (ok) written += static_cast<size_t>(n);
    }
    ok = ok && ::fsync(fd) == 0;
    ::close(fd);
    if (!ok || ::rename(temp.c_str(), path.c_str()) != 0) {
        ::unlink(temp.c_str());
        throw std::runtime_error("无法写入私有文件");
    }
}
std::string read_cookie() {
    const fs::path path = data_dir() / "cookie";
    const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        if (errno == ENOENT) return {};
        throw std::runtime_error("cookie 必须是权限 0600 的普通文件");
    }
    struct stat info {};
    if (::fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || (info.st_mode & 077) != 0) {
        ::close(fd);
        throw std::runtime_error("cookie 必须是权限 0600 的普通文件");
    }
    std::string value(16385, '\0');
    const ssize_t got = ::read(fd, value.data(), value.size());
    ::close(fd);
    if (got < 0 || got > 16384) throw std::runtime_error("cookie 格式无效");
    value.resize(static_cast<size_t>(got));
    if (value.find_first_of("\r\n") != std::string::npos) throw std::runtime_error("cookie 格式无效");
    return value;
}
void save_cookie(const std::string& cookie) {
    if (cookie.find_first_of("\r\n") != std::string::npos) throw std::runtime_error("cookie 格式无效");
    write_private(data_dir() / "cookie", cookie);
}
Config parse_config(const std::string& text) {
    Config config;
    config.download_dir = home() / "Videos/Bilibili";
    std::istringstream lines(text);
    std::string line;
    bool top = true;
    while (std::getline(lines, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        if (line[0] == '[') {
            // Options from older versions (such as [danmaku_options]) are ignored.
            top = false;
            continue;
        }
        const auto eq = line.find('=');
        if (!top || eq == std::string::npos) continue;
        const std::string key = trim(line.substr(0, eq));
        std::string value = trim(line.substr(eq + 1));
        if (!value.empty() && value[0] == '"') {
            const auto end = value.find('"', 1);
            value = end == std::string::npos ? value.substr(1) : value.substr(1, end - 1);
        } else {
            value = trim(value.substr(0, value.find('#')));
        }
        if (key == "report_history") config.report_history = value != "false";
        if (key == "subtitles") config.subtitles = value != "false";
        if (key == "quality") config.quality = std::strtoull(value.c_str(), nullptr, 10);
        if (key == "download_dir" && !value.empty()) config.download_dir = value;
    }
    return config;
}
Config load_config() {
    const char* base = std::getenv("XDG_CONFIG_HOME");
    const fs::path path = (base && *base ? fs::path(base) : home() / ".config") / "bilitui/config.toml";
    std::ifstream file(path);
    std::stringstream text;
    text << file.rdbuf();
    return parse_config(text.str());
}
std::vector<std::string> search_history() {
    std::ifstream file(data_dir() / "search.json");
    std::stringstream text;
    text << file.rdbuf();
    const Json value = Json::parse(text.str(), nullptr, false);
    std::vector<std::string> out;
    if (value.is_array()) {
        for (const Json& item : value) {
            if (item.is_string() && out.size() < 40) out.push_back(clean(item.get<std::string>()));
        }
    }
    return out;
}
void add_search(const std::string& query) {
    auto history = search_history();
    history.erase(std::remove(history.begin(), history.end(), query), history.end());
    history.insert(history.begin(), query);
    if (history.size() > 40) history.resize(40);
    write_private(data_dir() / "search.json", Json(history).dump());
}
}  // namespace bili
