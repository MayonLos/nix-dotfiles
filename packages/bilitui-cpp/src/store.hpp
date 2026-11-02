// Private files and the user-owned configuration. Paths match the original bilitui.
#pragma once
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace bili {
struct Config {
    bool report_history = true;
    bool subtitles = true;
    uint64_t quality = 0;
    std::filesystem::path download_dir;
};
std::filesystem::path data_dir();
std::filesystem::path cache_dir();
void private_dir(const std::filesystem::path& path);
void write_private(const std::filesystem::path& path, const std::string& bytes);
std::string read_cookie();
void save_cookie(const std::string& cookie);
Config parse_config(const std::string& text);
Config load_config();
std::vector<std::string> search_history();
void add_search(const std::string& query);
}  // namespace bili
