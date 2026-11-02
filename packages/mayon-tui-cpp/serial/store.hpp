// Persistent settings and history, in the same files and format as the Rust tool.
#pragma once
#include <filesystem>
#include <map>
#include <string>
#include <vector>

#include "codec.hpp"
#include "transport.hpp"

namespace serial {
struct Profile {
    Settings settings;
    Encoding encoding = Encoding::Utf8;
    std::string ending = "CRLF";
    std::string flash;
    std::string flash_dir;
};
struct Favorite {
    std::string name;
    std::string value;
    bool hex = false;
};
struct Config {
    std::map<std::string, Profile> devices;
    std::vector<Favorite> favorites;
    std::vector<std::string> highlights{"ERROR", "WARN", "FAULT"};
    size_t scrollback = 100000;
};
// Created mode 0600 and never over an existing file. Returns a descriptor or throws.
int private_file(const std::filesystem::path& path);
// The same text Rust's io::Error prints.
std::string os_error(int number);
std::string profile_json(const Profile& profile);
class Store {
public:
    // Both throw std::runtime_error. A damaged file is reported and left untouched.
    static Store load();
    static Store at(const std::filesystem::path& config_dir, const std::filesystem::path& data);
    void save() const;
    void remember(const std::string& line);

    Config config;
    std::vector<std::string> history;
    std::filesystem::path config_path;
    std::filesystem::path data;
};
}  // namespace serial
