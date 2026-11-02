// The fuzzy filter shared by every Clash page. It mirrors the Rust mayon-ui
// Matcher: every whitespace-separated term must match literally, by pinyin
// syllable, by pinyin initials, or (for short rows) by subsequence.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace clash {
using Ranges = std::vector<std::pair<size_t, size_t>>;
struct Matcher {
    explicit Matcher(std::string_view query);
    bool empty() const { return terms_.empty(); }
    // True when every term matched.
    bool matches(std::string_view text) const { return find(text).has_value(); }
    std::optional<Ranges> find(std::string_view text) const;
    // Ranges of the terms that did match, for painting hits.
    Ranges highlight(std::string_view text) const;

private:
    struct Term {
        std::u32string text;
        bool ascii = false;
    };
    std::vector<Term> terms_;
};
}  // namespace clash
