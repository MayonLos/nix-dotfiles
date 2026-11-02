#include "ui/text.hpp"

#include <array>
#include <cstdio>
#include <ctime>

namespace tui {
std::u32string decode(std::string_view text) {
    std::u32string out;
    out.reserve(text.size());
    for (size_t i = 0; i < text.size();) {
        const auto lead = static_cast<unsigned char>(text[i]);
        const size_t length = lead < 0x80 ? 1 : (lead >> 5) == 6 ? 2 : (lead >> 4) == 14 ? 3 : (lead >> 3) == 30 ? 4 : 0;
        if (length == 0 || i + length > text.size()) {
            out.push_back(U'�');
            ++i;
            continue;
        }
        char32_t value = length == 1 ? lead : lead & (0xFF >> (length + 1));
        bool valid = true;
        for (size_t k = 1; k < length; ++k) {
            const auto next = static_cast<unsigned char>(text[i + k]);
            valid = valid && (next & 0xC0) == 0x80;
            value = (value << 6) | (next & 0x3F);
        }
        constexpr std::array<char32_t, 5> minimum{0, 0, 0x80, 0x800, 0x10000};
        if (!valid || value < minimum[length] || value > 0x10FFFF || (value >= 0xD800 && value < 0xE000)) {
            out.push_back(U'�');
            ++i;
            continue;
        }
        out.push_back(value);
        i += length;
    }
    return out;
}
void append(std::string& out, char32_t ch) {
    if (ch < 0x80) {
        out += static_cast<char>(ch);
    } else if (ch < 0x800) {
        out += static_cast<char>(0xC0 | (ch >> 6));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    } else if (ch < 0x10000) {
        out += static_cast<char>(0xE0 | (ch >> 12));
        out += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (ch >> 18));
        out += static_cast<char>(0x80 | ((ch >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    }
}
std::string encode(std::u32string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const char32_t ch : text) append(out, ch);
    return out;
}
static void replace_all(std::string& text, std::string_view from, std::string_view to) {
    for (size_t at = 0; (at = text.find(from, at)) != std::string::npos; at += to.size()) text.replace(at, from.size(), to);
}
std::string clean(std::string_view text) {
    std::u32string kept;
    bool tag = false;
    for (const char32_t ch : decode(text)) {
        if (ch == U'<') {
            tag = true;
        } else if (ch == U'>') {
            tag = false;
        } else if (!tag && (ch == U'\n' || (ch >= 0x20 && ch != 0x7F && !(ch >= 0x80 && ch < 0xA0)))) {
            kept.push_back(ch);
        }
    }
    std::string out = encode(kept);
    replace_all(out, "&lt;", "<");
    replace_all(out, "&gt;", ">");
    replace_all(out, "&quot;", "\"");
    replace_all(out, "&#39;", "'");
    replace_all(out, "&amp;", "&");
    return out;
}
std::string count(uint64_t value) {
    if (value < 10000) return std::to_string(value);
    char buffer[32];
    std::snprintf(buffer, sizeof buffer, "%.1f万", static_cast<double>(value) / 10000.0);
    return buffer;
}
std::string seconds_text(uint64_t seconds) {
    char buffer[40];
    if (seconds >= 3600) {
        std::snprintf(buffer, sizeof buffer, "%llu:%02llu:%02llu", static_cast<unsigned long long>(seconds / 3600),
                      static_cast<unsigned long long>(seconds / 60 % 60), static_cast<unsigned long long>(seconds % 60));
    } else {
        std::snprintf(buffer, sizeof buffer, "%llu:%02llu", static_cast<unsigned long long>(seconds / 60),
                      static_cast<unsigned long long>(seconds % 60));
    }
    return buffer;
}
std::string normalize_duration(std::string_view text) {
    uint64_t total = 0;
    uint64_t part = 0;
    for (const char c : text) {
        if (c >= '0' && c <= '9') {
            if (part > 100000000) return std::string(text);
            part = part * 10 + static_cast<uint64_t>(c - '0');
        } else if (c == ':') {
            total = total * 60 + part;
            part = 0;
        } else {
            return clean(text);
        }
    }
    return seconds_text(total * 60 + part);
}
std::string date_text(uint64_t epoch) {
    if (epoch == 0) return {};
    const auto when = static_cast<time_t>(epoch);
    std::tm local{};
    localtime_r(&when, &local);
    char buffer[16];
    std::strftime(buffer, sizeof buffer, "%Y-%m-%d", &local);
    return buffer;
}
std::string form_encode(std::string_view value) {
    static constexpr char hex[] = "0123456789ABCDEF";
    std::string out;
    for (const char raw : value) {
        const auto c = static_cast<unsigned char>(raw);
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            out += raw;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}
std::string trim(std::string_view value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string_view::npos) return {};
    return std::string(value.substr(first, value.find_last_not_of(" \t\r\n") - first + 1));
}
std::vector<std::string> split_words(std::string_view value) {
    std::vector<std::string> out;
    size_t at = 0;
    while (at < value.size()) {
        const auto start = value.find_first_not_of(" \t\r\n", at);
        if (start == std::string_view::npos) break;
        const auto end = value.find_first_of(" \t\r\n", start);
        out.emplace_back(value.substr(start, end == std::string_view::npos ? end : end - start));
        if (end == std::string_view::npos) break;
        at = end;
    }
    return out;
}
}  // namespace tui
