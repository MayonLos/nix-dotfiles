#include "core/model.hpp"

#include "ui/text.hpp"

namespace bili {
static const Json null_json;
static const Json& at(const Json& value, const char* key) {
    if (!value.is_object()) return null_json;
    const auto found = value.find(key);
    return found == value.end() ? null_json : *found;
}
static const Json& first(const Json& value, std::initializer_list<const char*> keys) {
    for (const char* key : keys) {
        const Json& item = at(value, key);
        if (!item.is_null()) return item;
    }
    return null_json;
}
uint64_t number(const Json& value) {
    if (value.is_number_unsigned()) return value.get<uint64_t>();
    if (value.is_number_integer()) return value.get<int64_t>() > 0 ? static_cast<uint64_t>(value.get<int64_t>()) : 0;
    if (value.is_string()) {
        uint64_t out = 0;
        for (const char c : value.get_ref<const std::string&>()) {
            if (c < '0' || c > '9' || out > UINT64_MAX / 11) return 0;
            out = out * 10 + static_cast<uint64_t>(c - '0');
        }
        return out;
    }
    return 0;
}
std::string str(const Json& value, const char* key) {
    const Json& item = at(value, key);
    return item.is_string() ? item.get<std::string>() : std::string{};
}
std::string Video::key() const {
    if (kind == Kind::User) return "up:" + std::to_string(mid);
    if (kind == Kind::Folder) return "folder:" + std::to_string(count) + title;
    if (kind == Kind::Header) return "header:" + title;
    return bvid;
}
Video parse_video(const Json& v) {
    Video out;
    const Json& owner = first(v, {"owner", "upper"});
    const Json* stat = &first(v, {"stat", "cnt_info"});
    if (stat->is_null()) stat = &v;
    out.bvid = clean(str(v, "bvid"));
    if (out.bvid.empty()) out.bvid = clean(str(v, "bv_id"));
    out.aid = number(first(v, {"aid", "id"}));
    out.cid = number(at(v, "cid"));
    out.title = clean(str(v, "title"));
    if (out.title.empty()) out.title = clean(str(v, "name"));
    std::string up = str(owner, "name");
    if (up.empty()) up = str(v, "author");
    if (up.empty()) up = str(v, "author_name");
    out.up = clean(up);
    out.mid = number(first(owner, {"mid"}));
    if (out.mid == 0) out.mid = number(first(v, {"mid", "author_mid"}));
    out.cover = str(v, "pic");
    if (out.cover.empty()) out.cover = str(v, "cover");
    out.views = number(first(*stat, {"view", "play"}));
    out.likes = number(at(*stat, "like"));
    out.pubdate = number(first(v, {"pubdate", "pubtime"}));
    out.count = number(first(v, {"videos", "page"}));
    const Json& duration = first(v, {"duration", "duration_text"});
    out.duration = duration.is_string() ? normalize_duration(duration.get_ref<const std::string&>()) : seconds_text(number(duration));
    std::string description = str(v, "desc");
    if (description.empty()) description = str(v, "description");
    if (description.empty()) description = str(v, "intro");
    out.description = clean(description);
    const Json& progress = at(v, "progress");
    if (progress.is_number_integer()) out.progress = progress.get<int64_t>();
    const Json& pages = at(v, "pages");
    if (pages.is_array()) {
        for (const Json& page : pages) {
            out.parts.push_back({number(at(page, "cid")), number(at(page, "page")), clean(str(page, "part")), number(at(page, "duration"))});
        }
    }
    const Json& sections = at(at(v, "ugc_season"), "sections");
    if (sections.is_array()) {
        for (const Json& section : sections) {
            const Json& episodes = at(section, "episodes");
            if (!episodes.is_array()) continue;
            for (const Json& episode : episodes) {
                const Json& arc = at(episode, "arc");
                Video item = parse_video(arc.is_null() ? episode : arc);
                if (item.bvid.empty()) item.bvid = clean(str(episode, "bvid"));
                if (item.aid == 0) item.aid = number(at(episode, "aid"));
                if (item.cid == 0) item.cid = number(at(episode, "cid"));
                const std::string title = clean(str(episode, "title"));
                if (!title.empty()) item.title = title;
                out.collection.push_back(std::move(item));
            }
        }
    }
    return out;
}
std::vector<Video> parse_videos(const Json& value) {
    std::vector<Video> out;
    if (!value.is_array()) return out;
    for (const Json& item : value) {
        Video video = parse_video(item);
        if (!video.bvid.empty()) out.push_back(std::move(video));
    }
    return out;
}
}  // namespace bili
