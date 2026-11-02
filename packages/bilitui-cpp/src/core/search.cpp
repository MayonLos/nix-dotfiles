#include "core/search.hpp"

#include <algorithm>
#include <string>

#include "core/text.hpp"

namespace bili {
static const char kTable[] =
#include "core/pinyin_table.inc"
    ;
static const std::vector<std::string_view>& table() {
    static const std::vector<std::string_view> words = [] {
        std::vector<std::string_view> out;
        out.reserve(0xA000 - 0x4E00);
        std::string_view rest(kTable);
        while (true) {
            const auto space = rest.find(' ');
            out.push_back(rest.substr(0, space));
            if (space == std::string_view::npos) break;
            rest.remove_prefix(space + 1);
        }
        return out;
    }();
    return words;
}
static char32_t lower(char32_t ch) { return ch >= U'A' && ch <= U'Z' ? ch + 32 : ch; }
struct Index {
    std::u32string chars;
    std::vector<size_t> map;
    std::optional<std::pair<size_t, size_t>> find(std::u32string_view term) const {
        const auto at = std::u32string_view(chars).find(term);
        if (at == std::u32string_view::npos) return std::nullopt;
        return std::make_pair(map[at], map[at + term.size() - 1] + 1);
    }
};
std::optional<Match> match(std::string_view query, std::string_view text) {
    Match out;
    const auto terms = split_words(query);
    if (terms.empty()) return out;
    Index literal, full, initials;
    const std::u32string source = decode(text);
    const auto& words = table();
    for (size_t i = 0; i < source.size(); ++i) {
        const char32_t ch = lower(source[i]);
        literal.chars.push_back(ch);
        literal.map.push_back(i);
        if (ch >= 0x4E00 && ch < 0xA000 && !words[ch - 0x4E00].empty()) {
            const std::string_view word = words[ch - 0x4E00];
            initials.chars.push_back(static_cast<char32_t>(word[0]));
            initials.map.push_back(i);
            for (const char letter : word) {
                full.chars.push_back(static_cast<char32_t>(letter));
                full.map.push_back(i);
            }
        } else {
            initials.chars.push_back(ch);
            initials.map.push_back(i);
            full.chars.push_back(ch);
            full.map.push_back(i);
        }
    }
    for (const std::string& raw : terms) {
        std::u32string term = decode(raw);
        std::transform(term.begin(), term.end(), term.begin(), lower);
        if (const auto hit = literal.find(term)) {
            out.score += 300;
            out.ranges.push_back(*hit);
        } else if (const auto hit = full.find(term)) {
            out.score += 200;
            out.ranges.push_back(*hit);
        } else if (const auto hit = initials.find(term)) {
            out.score += 150;
            out.ranges.push_back(*hit);
        } else {
            if (source.size() > 64) return std::nullopt;
            size_t needle = 0;
            std::vector<std::pair<size_t, size_t>> ranges;
            for (size_t i = 0; i < literal.chars.size() && needle < term.size(); ++i) {
                if (literal.chars[i] == term[needle]) {
                    ranges.emplace_back(i, i + 1);
                    ++needle;
                }
            }
            if (needle != term.size()) return std::nullopt;
            out.score += 50;
            out.ranges.insert(out.ranges.end(), ranges.begin(), ranges.end());
        }
    }
    std::sort(out.ranges.begin(), out.ranges.end());
    std::vector<std::pair<size_t, size_t>> merged;
    for (const auto& range : out.ranges) {
        if (!merged.empty() && range.first <= merged.back().second) {
            merged.back().second = std::max(merged.back().second, range.second);
        } else {
            merged.push_back(range);
        }
    }
    out.ranges = std::move(merged);
    return out;
}
}  // namespace bili
