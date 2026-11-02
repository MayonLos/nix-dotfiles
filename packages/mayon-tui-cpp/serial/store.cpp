#include "store.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <nlohmann/json.hpp>
#include <optional>
#include <stdexcept>

namespace serial {
namespace fs = std::filesystem;
using nlohmann::json;
using nlohmann::ordered_json;
namespace {
template <class T>
T unsigned_field(const json& value) {
    if (!value.is_number_unsigned()) throw std::runtime_error("invalid type: expected an unsigned integer");
    const auto number = value.get<uint64_t>();
    if (number > std::numeric_limits<T>::max()) throw std::runtime_error("invalid value: integer out of range");
    return static_cast<T>(number);
}
// Settings and favourites have no field defaults in the format; profiles and the config do.
Settings settings_from(const json& value) {
    Settings out;
    out.baud = unsigned_field<uint32_t>(value.at("baud"));
    out.bits = unsigned_field<uint8_t>(value.at("bits"));
    out.parity = value.at("parity").get<std::string>();
    out.stop = unsigned_field<uint8_t>(value.at("stop"));
    out.flow = value.at("flow").get<std::string>();
    out.dtr = value.at("dtr").get<bool>();
    out.rts = value.at("rts").get<bool>();
    return out;
}
Encoding encoding_from(const json& value) {
    const auto name = value.get<std::string>();
    if (name == "Utf8") return Encoding::Utf8;
    if (name == "Gbk") return Encoding::Gbk;
    throw std::runtime_error("unknown variant `" + name + "`, expected `Utf8` or `Gbk`");
}
Profile profile_from(const json& value) {
    if (!value.is_object()) throw std::runtime_error("invalid type: expected a profile");
    Profile out;
    if (value.contains("settings")) out.settings = settings_from(value["settings"]);
    if (value.contains("encoding")) out.encoding = encoding_from(value["encoding"]);
    if (value.contains("ending")) out.ending = value["ending"].get<std::string>();
    if (value.contains("flash")) out.flash = value["flash"].get<std::string>();
    if (value.contains("flash_dir")) out.flash_dir = value["flash_dir"].get<std::string>();
    return out;
}
Config config_from(const json& value) {
    if (!value.is_object()) throw std::runtime_error("invalid type: expected a config");
    Config out;
    if (value.contains("devices")) {
        if (!value["devices"].is_object()) throw std::runtime_error("invalid type: devices");
        for (const auto& [key, profile] : value["devices"].items()) out.devices.emplace(key, profile_from(profile));
    }
    if (value.contains("favorites")) {
        if (!value["favorites"].is_array()) throw std::runtime_error("invalid type: favorites");
        for (const json& item : value["favorites"]) {
            out.favorites.push_back(Favorite{item.at("name").get<std::string>(), item.at("value").get<std::string>(), item.at("hex").get<bool>()});
        }
    }
    if (value.contains("highlights")) out.highlights = value["highlights"].get<std::vector<std::string>>();
    if (value.contains("scrollback")) out.scrollback = unsigned_field<size_t>(value["scrollback"]);
    return out;
}
ordered_json to_json(const Profile& profile) {
    ordered_json settings = ordered_json::object();
    settings["baud"] = profile.settings.baud;
    settings["bits"] = profile.settings.bits;
    settings["parity"] = profile.settings.parity;
    settings["stop"] = profile.settings.stop;
    settings["flow"] = profile.settings.flow;
    settings["dtr"] = profile.settings.dtr;
    settings["rts"] = profile.settings.rts;
    ordered_json out = ordered_json::object();
    out["settings"] = std::move(settings);
    out["encoding"] = encoding_name(profile.encoding);
    out["ending"] = profile.ending;
    out["flash"] = profile.flash;
    out["flash_dir"] = profile.flash_dir;
    return out;
}
std::optional<std::string> read_file(const fs::path& path) {
    const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        if (errno == ENOENT) return std::nullopt;
        throw std::runtime_error(os_error(errno));
    }
    std::string text;
    char buffer[65536];
    while (true) {
        const ssize_t got = ::read(fd, buffer, sizeof buffer);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) {
            const int error = errno;
            ::close(fd);
            throw std::runtime_error(os_error(error));
        }
        if (got == 0) break;
        text.append(buffer, static_cast<size_t>(got));
    }
    ::close(fd);
    return text;
}
void write_all(int fd, std::string_view text) {
    while (!text.empty()) {
        const ssize_t wrote = ::write(fd, text.data(), text.size());
        if (wrote < 0) {
            if (errno == EINTR) continue;
            throw std::runtime_error(os_error(errno));
        }
        text.remove_prefix(static_cast<size_t>(wrote));
    }
}
void atomic_json(const fs::path& path, const ordered_json& value) {
    fs::path temporary = path;
    temporary.replace_extension(std::to_string(::getpid()) + ".tmp");
    const int fd = private_file(temporary);
    try {
        write_all(fd, value.dump(2, ' ', false, ordered_json::error_handler_t::replace) + "\n");
        if (::fsync(fd) != 0 || ::rename(temporary.c_str(), path.c_str()) != 0) throw std::runtime_error(os_error(errno));
        ::close(fd);
    } catch (...) {
        ::close(fd);
        ::unlink(temporary.c_str());
        throw;
    }
}
void private_dir(const fs::path& path) {
    std::error_code error;
    fs::create_directories(path, error);
    if (error) throw std::runtime_error(path.string() + ": " + error.message());
    if (::chmod(path.c_str(), 0700) != 0) throw std::runtime_error(path.string() + ": " + os_error(errno));
}
fs::path xdg(const char* variable, const char* fallback) {
    const char* value = std::getenv(variable);
    if (value != nullptr && *value != '\0') return value;
    const char* home = std::getenv("HOME");
    if (home == nullptr) throw std::runtime_error("HOME 未设置");
    return fs::path(home) / fallback;
}
}  // namespace
std::string os_error(int number) { return std::string(std::strerror(number)) + " (os error " + std::to_string(number) + ")"; }
std::string profile_json(const Profile& profile) { return to_json(profile).dump(); }
int private_file(const fs::path& path) {
    const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) throw std::runtime_error(os_error(errno));
    return fd;
}
Store Store::load() { return at(xdg("XDG_CONFIG_HOME", ".config") / "serial-mayon", xdg("XDG_DATA_HOME", ".local/share") / "serial-mayon"); }
Store Store::at(const fs::path& config_dir, const fs::path& data) {
    private_dir(config_dir);
    private_dir(data);
    private_dir(data / "logs");
    Store store;
    store.config_path = config_dir / "config.json";
    store.data = data;
    try {
        if (const auto text = read_file(store.config_path)) store.config = config_from(json::parse(*text));
        if (const auto text = read_file(data / "history.json")) store.history = json::parse(*text).get<std::vector<std::string>>();
    } catch (const json::exception& error) {
        throw std::runtime_error(error.what());
    }
    return store;
}
void Store::save() const {
    ordered_json devices = ordered_json::object();
    for (const auto& [key, profile] : config.devices) devices[key] = to_json(profile);
    ordered_json favorites = ordered_json::array();
    for (const Favorite& favorite : config.favorites) {
        ordered_json item = ordered_json::object();
        item["name"] = favorite.name;
        item["value"] = favorite.value;
        item["hex"] = favorite.hex;
        favorites.push_back(std::move(item));
    }
    ordered_json out = ordered_json::object();
    out["devices"] = std::move(devices);
    out["favorites"] = std::move(favorites);
    out["highlights"] = config.highlights;
    out["scrollback"] = config.scrollback;
    atomic_json(config_path, out);
    atomic_json(data / "history.json", ordered_json(history));
}
void Store::remember(const std::string& line) {
    if (history.empty() || history.back() != line) history.push_back(line);
    if (history.size() > 1000) history.erase(history.begin(), history.end() - 1000);
}
}  // namespace serial
