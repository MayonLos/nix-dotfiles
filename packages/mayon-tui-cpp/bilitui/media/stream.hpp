// Stream selection, AI/CC subtitle conversion and cover decoding.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "core/model.hpp"
#include "net/api.hpp"

#include "ui/terminal.hpp"

namespace bili {
struct Stream {
    std::string video;
    std::string audio;
    uint64_t quality = 0;
    std::vector<std::pair<uint64_t, std::string>> choices;
};
Stream parse_stream(const Json& data, uint64_t quality);
Stream resolve_stream(Api& api, const std::string& bvid, uint64_t cid, uint64_t quality, const CancelFlag& cancel = {});

struct Subtitle {
    std::string language;
    std::string title;
    std::string url;
};
struct PlayerInfo {
    uint64_t last_cid = 0;
    uint64_t last_seconds = 0;
    std::vector<Subtitle> subtitles;
};
PlayerInfo parse_player_info(const Json& data);
PlayerInfo fetch_player_info(Api& api, const std::string& bvid, uint64_t cid, const CancelFlag& cancel = {});
// Human subtitles first, then AI Chinese, then anything else.
std::optional<Subtitle> preferred_subtitle(const std::vector<Subtitle>& subtitles);
std::string subtitle_to_srt(const Json& body);
std::string fetch_subtitle_srt(const Subtitle& subtitle, const CancelFlag& cancel = {});

// Requests a small JPEG rendition, so only one decoder ever sees remote image data.
std::optional<Image> fetch_cover(const std::string& url, const CancelFlag& cancel = {});
std::optional<Image> decode_jpeg(const std::string& bytes);
}  // namespace bili
