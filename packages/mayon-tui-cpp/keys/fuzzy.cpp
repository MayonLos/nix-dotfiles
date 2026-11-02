#include "fuzzy.hpp"

#include <algorithm>

#include "model.hpp"
#include "ui/search.hpp"
#include "ui/text.hpp"

namespace keys {
namespace {
std::string_view syllable(char32_t ch) { return tui::pinyin_syllable(ch); }
bool is_han(char32_t ch) { return (ch >= 0x3400 && ch <= 0x4DBF) || (ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0xF900 && ch <= 0xFAFF) || (ch >= 0x20000 && ch <= 0x3134F); }
char32_t lower(char32_t ch) { return ch >= U'A' && ch <= U'Z' ? ch + 32 : ch; }
void add(Indexed& index, char32_t ch, size_t at) {
    index.chars.push_back(ch);
    index.map.push_back(at);
}
Ranges merge(Ranges ranges) {
    std::stable_sort(ranges.begin(), ranges.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    Ranges merged;
    for (const auto& range : ranges) {
        if (!merged.empty() && range.first <= merged.back().second) merged.back().second = std::max(merged.back().second, range.second);
        else merged.push_back(range);
    }
    return merged;
}
}  // namespace

Ranges Indexed::mapped_range(size_t from, size_t to) const {
    Ranges result;
    for (size_t i = from; i < to; ++i) {
        const size_t original = map[i];
        if (!result.empty() && result.back().second == original) ++result.back().second;
        else if (result.empty() || result.back().second <= original) result.emplace_back(original, original + 1);
    }
    return result;
}
std::optional<Ranges> Indexed::find(std::u32string_view query) const {
    if (query.empty() || query.size() > chars.size()) return std::nullopt;
    const auto at = std::u32string_view(chars).find(query);
    if (at == std::u32string_view::npos) return std::nullopt;
    return mapped_range(at, at + query.size());
}
std::optional<Ranges> Indexed::subsequence(std::u32string_view query) const {
    if (query.empty()) return Ranges{};
    Ranges out;
    size_t needle = 0;
    for (size_t i = 0; i < chars.size(); ++i) {
        if (chars[i] != query[needle]) continue;
        const Ranges one = mapped_range(i, i + 1);
        out.insert(out.end(), one.begin(), one.end());
        if (++needle == query.size()) return out;
    }
    return std::nullopt;
}
SearchText::SearchText(std::string_view text) {
    const std::u32string source = tui::decode(text);
    short_ = source.size() <= 80;
    for (size_t i = 0; i < source.size(); ++i) add(literal_, lower(source[i]), i);
    if (!std::any_of(source.begin(), source.end(), is_han)) return;
    Indexed full, initials;
    for (size_t i = 0; i < source.size(); ++i) {
        const char32_t ch = source[i];
        if (is_han(ch)) {
            const std::string_view word = syllable(ch);
            for (const char letter : word) add(full, static_cast<char32_t>(letter), i);
            add(initials, word.empty() ? ch : static_cast<char32_t>(word[0]), i);
        } else {
            add(full, lower(ch), i);
            add(initials, lower(ch), i);
        }
    }
    pinyin_.emplace(std::move(full), std::move(initials));
}
Matcher::Matcher(std::string_view query) {
    std::u32string term;
    for (const char32_t ch : tui::decode(query)) {
        if (is_space(ch)) {
            if (!term.empty()) terms_.push_back(std::exchange(term, {}));
        } else {
            term.push_back(lower(ch));
        }
    }
    if (!term.empty()) terms_.push_back(std::move(term));
}
namespace {
std::optional<std::pair<uint32_t, Ranges>> match_term(const Indexed& literal, const std::optional<std::pair<Indexed, Indexed>>& pinyin, bool is_short, const std::u32string& term) {
    if (auto hit = literal.find(term)) return std::make_pair(400U, std::move(*hit));
    if (pinyin && std::any_of(term.begin(), term.end(), [](char32_t ch) { return ch >= U'a' && ch <= U'z'; })) {
        if (auto hit = pinyin->first.find(term)) return std::make_pair(300U, std::move(*hit));
        if (auto hit = pinyin->second.find(term)) return std::make_pair(200U, std::move(*hit));
    }
    if (!is_short || term.size() <= 1) return std::nullopt;
    if (auto hit = literal.subsequence(term)) return std::make_pair(100U, std::move(*hit));
    if (pinyin) {
        if (auto hit = pinyin->second.subsequence(term)) return std::make_pair(100U, std::move(*hit));
    }
    return std::nullopt;
}
}  // namespace
std::optional<Found> Matcher::find_in(const SearchText& text) const {
    Found out;
    for (const std::u32string& term : terms_) {
        auto found = match_term(text.literal_, text.pinyin_, text.short_, term);
        if (!found) return std::nullopt;
        out.score += found->first;
        out.ranges.insert(out.ranges.end(), found->second.begin(), found->second.end());
    }
    out.ranges = merge(std::move(out.ranges));
    return out;
}
Ranges Matcher::highlight(std::string_view text) const {
    if (terms_.empty()) return {};
    const SearchText index(text);
    Ranges out;
    for (const std::u32string& term : terms_) {
        if (auto found = match_term(index.literal_, index.pinyin_, index.short_, term)) out.insert(out.end(), found->second.begin(), found->second.end());
    }
    return merge(std::move(out));
}
}  // namespace keys
