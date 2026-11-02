// Parsed Bilibili content. Every remote string passes through clean().
#pragma once
#include <cstdint>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace tui {}
namespace bili {
using namespace tui;
using Json = nlohmann::json;
enum class Kind { Video, User, Folder, Header };
struct Part {
    uint64_t cid = 0;
    uint64_t page = 0;
    std::string title;
    uint64_t seconds = 0;
};
struct Video {
    Kind kind = Kind::Video;
    std::string bvid;
    uint64_t aid = 0;
    uint64_t cid = 0;
    std::string title;
    std::string up;
    uint64_t mid = 0;
    std::string cover;
    uint64_t views = 0;
    uint64_t likes = 0;
    uint64_t pubdate = 0;
    uint64_t count = 0;  // Folder size, or number of parts when the listing reports it.
    int64_t progress = 0;  // Seconds watched; -1 means finished.
    std::string duration;
    std::string description;
    std::vector<Part> parts;
    std::vector<Video> collection;
    std::string link() const { return "https://www.bilibili.com/video/" + bvid; }
    std::string key() const;
};
uint64_t number(const Json& value);
std::string str(const Json& value, const char* key);
Video parse_video(const Json& value);
std::vector<Video> parse_videos(const Json& value);
}  // namespace bili
