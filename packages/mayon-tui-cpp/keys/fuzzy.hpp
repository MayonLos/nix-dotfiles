// Private: the Rust tool's filter. ui/search.hpp scores differently and has no strong_score
// threshold, and these raw Mango rows rely on both to drop weak subsequence hits.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace keys {
using Ranges = std::vector<std::pair<size_t, size_t>>;
struct Found {
    uint32_t score = 0;
    Ranges ranges;  // Code point offsets, half open and merged.
};
struct Indexed {
    std::u32string chars;
    std::vector<size_t> map;
    std::optional<Ranges> find(std::u32string_view query) const;
    std::optional<Ranges> subsequence(std::u32string_view query) const;
    Ranges mapped_range(size_t from, size_t to) const;
};
class SearchText {
public:
    explicit SearchText(std::string_view text);

private:
    friend class Matcher;
    Indexed literal_;
    std::optional<std::pair<Indexed, Indexed>> pinyin_;  // Full syllables, initials.
    bool short_ = false;
};
class Matcher {
public:
    explicit Matcher(std::string_view query);
    // Scores at or above this hit literally or by pinyin on every term; lower scores
    // contain a subsequence hit, which is only a fallback.
    uint32_t strong_score() const { return static_cast<uint32_t>(terms_.size()) * 200; }
    std::optional<Found> find_in(const SearchText& text) const;
    bool matches(std::string_view text) const { return find_in(SearchText(text)).has_value(); }
    // What to colour: every term that hits, even when another term misses.
    Ranges highlight(std::string_view text) const;

private:
    std::vector<std::u32string> terms_;
};
}  // namespace keys
