#include "media/stream.hpp"

#include <turbojpeg.h>

#include <algorithm>
#include <cstdio>
#include <stdexcept>
#include <tuple>

#include "ui/text.hpp"

namespace bili {
static std::string best_address(const Json& item) {
    std::vector<std::string> candidates;
    for (const char* key : {"baseUrl", "base_url"}) {
        if (item.contains(key) && item[key].is_string()) candidates.push_back(item[key].get<std::string>());
    }
    for (const char* key : {"backupUrl", "backup_url"}) {
        if (item.contains(key) && item[key].is_array()) {
            for (const Json& url : item[key]) {
                if (url.is_string()) candidates.push_back(url.get<std::string>());
            }
        }
    }
    std::vector<std::string> trusted;
    for (const auto& raw : candidates) {
        try {
            trusted.push_back(trusted_media_url(raw));
        } catch (const std::exception&) {
        }
    }
    // Prefer ordinary HTTPS CDN hosts over peer/edge ports.
    const auto rank = [](const std::string& url) {
        const auto host = url.find("://") + 3;
        const auto end = url.find('/', host);
        const std::string authority = url.substr(host, end == std::string::npos ? end : end - host);
        return std::make_tuple(authority.find(':') != std::string::npos, authority.rfind("upos-", 0) != 0);
    };
    std::stable_sort(trusted.begin(), trusted.end(), [&](const auto& a, const auto& b) { return rank(a) < rank(b); });
    return trusted.empty() ? std::string{} : trusted.front();
}
Stream parse_stream(const Json& data, uint64_t quality) {
    Stream out;
    if (!data.is_object()) throw std::runtime_error("没有可用流，可能需登录或会员");
    if (data.contains("accept_quality") && data["accept_quality"].is_array()) {
        const Json& names = data.contains("accept_description") ? data["accept_description"] : Json::array();
        for (size_t i = 0; i < data["accept_quality"].size(); ++i) {
            const std::string name = names.is_array() && i < names.size() && names[i].is_string() ? clean(names[i].get<std::string>()) : "DASH";
            out.choices.emplace_back(number(data["accept_quality"][i]), name);
        }
    }
    if (data.contains("dash") && data["dash"].is_object() && data["dash"].contains("video") && data["dash"]["video"].is_array()) {
        const Json* best = nullptr;
        std::tuple<uint64_t, bool, uint64_t> best_rank{};
        for (const Json& item : data["dash"]["video"]) {
            const uint64_t id = number(item.value("id", Json()));
            if (quality != 0 && id > quality) continue;
            const std::tuple rank{id, number(item.value("codecid", Json())) == 7, number(item.value("bandwidth", Json()))};
            if (!best || rank > best_rank) {
                best = &item;
                best_rank = rank;
            }
        }
        if (!best) throw std::runtime_error("所选清晰度不可用");
        out.video = best_address(*best);
        if (out.video.empty()) throw std::runtime_error("视频流缺失");
        out.quality = std::get<0>(best_rank);
        if (data["dash"].contains("audio") && data["dash"]["audio"].is_array()) {
            const Json* audio = nullptr;
            for (const Json& item : data["dash"]["audio"]) {
                if (!audio || number(item.value("bandwidth", Json())) > number(audio->value("bandwidth", Json()))) audio = &item;
            }
            if (audio) out.audio = best_address(*audio);
        }
        return out;
    }
    if (!data.contains("durl") || !data["durl"].is_array() || data["durl"].empty()) throw std::runtime_error("没有可用流，可能需登录或会员");
    if (data["durl"].size() > 1) throw std::runtime_error("此视频使用旧式多段流，暂不支持");
    out.video = trusted_media_url(str(data["durl"][0], "url"));
    out.quality = number(data.value("quality", Json()));
    return out;
}
Stream resolve_stream(Api& api, const std::string& bvid, uint64_t cid, uint64_t quality, const CancelFlag& cancel) {
    const Json data = api.signed_get("/x/player/wbi/playurl",
                                     {{"bvid", bvid},
                                      {"cid", std::to_string(cid)},
                                      {"qn", quality == 0 ? "127" : std::to_string(quality)},
                                      {"fnval", "4048"},
                                      {"fnver", "0"},
                                      {"fourk", "1"}},
                                     cancel);
    return parse_stream(data, quality);
}
PlayerInfo parse_player_info(const Json& data) {
    PlayerInfo out;
    if (!data.is_object()) return out;
    out.last_cid = number(data.value("last_play_cid", Json()));
    out.last_seconds = number(data.value("last_play_time", Json())) / 1000;
    if (data.contains("subtitle") && data["subtitle"].is_object() && data["subtitle"].contains("subtitles") && data["subtitle"]["subtitles"].is_array()) {
        for (const Json& item : data["subtitle"]["subtitles"]) {
            const std::string url = str(item, "subtitle_url");
            if (!url.empty()) out.subtitles.push_back({clean(str(item, "lan")), clean(str(item, "lan_doc")), url});
        }
    }
    return out;
}
PlayerInfo fetch_player_info(Api& api, const std::string& bvid, uint64_t cid, const CancelFlag& cancel) {
    return parse_player_info(api.signed_get("/x/player/wbi/v2", {{"bvid", bvid}, {"cid", std::to_string(cid)}}, cancel));
}
std::optional<Subtitle> preferred_subtitle(const std::vector<Subtitle>& subtitles) {
    const auto find = [&](auto predicate) -> std::optional<Subtitle> {
        const auto hit = std::find_if(subtitles.begin(), subtitles.end(), predicate);
        return hit == subtitles.end() ? std::nullopt : std::optional(*hit);
    };
    if (auto human = find([](const Subtitle& s) { return s.language.rfind("zh", 0) == 0; })) return human;
    if (auto ai = find([](const Subtitle& s) { return s.language.rfind("ai-zh", 0) == 0; })) return ai;
    return subtitles.empty() ? std::nullopt : std::optional(subtitles.front());
}
static std::string srt_time(double seconds) {
    const auto millis = static_cast<uint64_t>(std::max(seconds, 0.0) * 1000.0 + 0.5);
    char buffer[40];
    std::snprintf(buffer, sizeof buffer, "%02llu:%02llu:%02llu,%03llu", static_cast<unsigned long long>(millis / 3600000),
                  static_cast<unsigned long long>(millis / 60000 % 60), static_cast<unsigned long long>(millis / 1000 % 60),
                  static_cast<unsigned long long>(millis % 1000));
    return buffer;
}
std::string subtitle_to_srt(const Json& body) {
    std::string out;
    if (!body.is_object() || !body.contains("body") || !body["body"].is_array()) return out;
    size_t index = 0;
    for (const Json& line : body["body"]) {
        if (!line.is_object() || !line.contains("from") || !line.contains("to") || !line["from"].is_number() || !line["to"].is_number()) continue;
        std::string text = clean(str(line, "content"));
        if (trim(text).empty() || ++index > 20000) continue;
        out += std::to_string(index) + "\n" + srt_time(line["from"].get<double>()) + " --> " + srt_time(line["to"].get<double>()) + "\n" + text + "\n\n";
    }
    return out;
}
std::string fetch_subtitle_srt(const Subtitle& subtitle, const CancelFlag& cancel) {
    HttpRequest request;
    request.url = trusted_media_url(subtitle.url);
    request.cancel = cancel;
    request.headers.emplace_back("Referer: https://www.bilibili.com/");
    const HttpResponse response = http_perform(request);
    if (response.status != 200) throw std::runtime_error("字幕暂不可用");
    const Json body = Json::parse(response.body, nullptr, false);
    if (body.is_discarded()) throw std::runtime_error("字幕数据无效");
    return subtitle_to_srt(body);
}
std::optional<Image> decode_jpeg(const std::string& bytes) {
    tjhandle handle = tj3Init(TJINIT_DECOMPRESS);
    if (!handle) return std::nullopt;
    Image image;
    const auto* data = reinterpret_cast<const unsigned char*>(bytes.data());
    bool ok = tj3DecompressHeader(handle, data, bytes.size()) == 0;
    if (ok) {
        image.width = tj3Get(handle, TJPARAM_JPEGWIDTH);
        image.height = tj3Get(handle, TJPARAM_JPEGHEIGHT);
        ok = image.width > 0 && image.height > 0 && image.width <= 2048 && image.height <= 2048;
    }
    if (ok) {
        image.rgb.resize(static_cast<size_t>(image.width) * static_cast<size_t>(image.height) * 3);
        ok = tj3Decompress8(handle, data, bytes.size(), image.rgb.data(), 0, TJPF_RGB) == 0;
    }
    tj3Destroy(handle);
    return ok ? std::optional(std::move(image)) : std::nullopt;
}
std::optional<Image> fetch_cover(const std::string& url, const CancelFlag& cancel) {
    if (url.empty()) return std::nullopt;
    HttpRequest request;
    request.url = trusted_media_url(url + "@480w_270h_1c.jpg");
    request.cancel = cancel;
    request.max_bytes = 4 * 1024 * 1024;
    request.headers.emplace_back("Referer: https://www.bilibili.com/");
    const HttpResponse response = http_perform(request);
    if (response.status != 200) return std::nullopt;
    return decode_jpeg(response.body);
}
}  // namespace bili
