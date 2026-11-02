#include "matcher.hpp"

#include <algorithm>
#include <unordered_map>

#include "ui/search.hpp"
#include "ui/text.hpp"

namespace clash {
namespace {
char32_t lower_char(char32_t ch) { return ch >= U'A' && ch <= U'Z' ? ch + 32 : ch; }
bool ascii_alpha(char32_t ch) { return (ch >= U'a' && ch <= U'z') || (ch >= U'A' && ch <= U'Z') || (ch >= U'0' && ch <= U'9'); }
struct Indexed {
    std::u32string chars;
    std::vector<size_t> map;
    std::optional<Ranges> find(const std::u32string& query) const {
        if (query.empty() || query.size() > chars.size()) return std::nullopt;
        const auto at = std::u32string_view(chars).find(query);
        if (at == std::u32string_view::npos) return std::nullopt;
        return mapped(at, query.size());
    }
    std::optional<Ranges> subsequence(const std::u32string& query) const {
        if (query.empty()) return Ranges{};
        std::vector<size_t> positions;
        positions.reserve(query.size());
        size_t needle = 0;
        for (size_t i = 0; i < chars.size() && needle < query.size(); ++i) {
            if (chars[i] == query[needle]) {
                positions.push_back(i);
                ++needle;
            }
        }
        if (needle != query.size()) return std::nullopt;
        Ranges out;
        for (const size_t position : positions) {
            const Ranges one = mapped(position, 1);
            out.insert(out.end(), one.begin(), one.end());
        }
        return out;
    }
    Ranges mapped(size_t at, size_t count) const {
        Ranges out;
        for (size_t i = at; i < at + count && i < map.size(); ++i) {
            const size_t original = map[i];
            if (!out.empty() && out.back().second == original) {
                out.back().second += 1;
            } else if (out.empty() || out.back().second <= original) {
                out.push_back({original, original + 1});
            }
        }
        return out;
    }
};
struct SearchText {
    std::u32string original;
    Indexed literal;
    std::optional<Indexed> full;
    std::optional<Indexed> initials;
    bool short_text = false;
};
SearchText index(std::string_view text) {
    SearchText out;
    out.original = tui::decode(text);
    bool has_han = false;
    for (const char32_t ch : out.original) {
        if (!tui::pinyin_syllable(ch).empty()) {
            has_han = true;
            break;
        }
    }
    Indexed full, initials;
    for (size_t i = 0; i < out.original.size(); ++i) {
        const char32_t ch = lower_char(out.original[i]);
        out.literal.chars.push_back(ch);
        out.literal.map.push_back(i);
        const std::string_view syllable = tui::pinyin_syllable(out.original[i]);
        if (has_han && !syllable.empty()) {
            initials.chars.push_back(static_cast<char32_t>(syllable.front()));
            initials.map.push_back(i);
            for (const char letter : syllable) {
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
    if (has_han) {
        out.full = std::move(full);
        out.initials = std::move(initials);
    }
    out.short_text = out.original.size() <= 80;
    return out;
}
std::optional<std::pair<uint32_t, Ranges>> match_term(const SearchText& text, const std::u32string& term) {
    if (const auto hit = text.literal.find(term)) return std::pair<uint32_t, Ranges>{400, *hit};
    bool alpha = false;
    for (const char32_t ch : term) alpha |= ascii_alpha(ch);
    if (alpha && text.full && text.initials) {
        if (const auto hit = text.full->find(term)) return std::pair<uint32_t, Ranges>{300, *hit};
        if (const auto hit = text.initials->find(term)) return std::pair<uint32_t, Ranges>{200, *hit};
    }
    if (!text.short_text || term.size() <= 1) return std::nullopt;
    if (const auto hit = text.literal.subsequence(term)) return std::pair<uint32_t, Ranges>{100, *hit};
    if (text.initials) {
        if (const auto hit = text.initials->subsequence(term)) return std::pair<uint32_t, Ranges>{100, *hit};
    }
    return std::nullopt;
}
Ranges merge_ranges(Ranges ranges) {
    std::sort(ranges.begin(), ranges.end());
    Ranges merged;
    for (const auto& range : ranges) {
        if (!merged.empty() && range.first <= merged.back().second) {
            merged.back().second = std::max(merged.back().second, range.second);
        } else {
            merged.push_back(range);
        }
    }
    return merged;
}
}  // namespace
Matcher::Matcher(std::string_view query) {
    for (const std::string& word : tui::split_words(query)) {
        Term term;
        term.text = tui::decode(word);
        for (char32_t& ch : term.text) {
            term.ascii |= ascii_alpha(ch);
            ch = lower_char(ch);
        }
        terms_.push_back(std::move(term));
    }
}
std::optional<Ranges> Matcher::find(std::string_view text) const {
    if (terms_.empty()) return Ranges{};
    const SearchText indexed = index(text);
    Ranges ranges;
    for (const Term& term : terms_) {
        const auto found = match_term(indexed, term.text);
        if (!found) return std::nullopt;
        ranges.insert(ranges.end(), found->second.begin(), found->second.end());
    }
    return merge_ranges(std::move(ranges));
}
Ranges Matcher::highlight(std::string_view text) const {
    if (terms_.empty()) return {};
    const SearchText indexed = index(text);
    Ranges ranges;
    for (const Term& term : terms_) {
        if (const auto found = match_term(indexed, term.text)) ranges.insert(ranges.end(), found->second.begin(), found->second.end());
    }
    return merge_ranges(std::move(ranges));
}
}  // namespace clash
