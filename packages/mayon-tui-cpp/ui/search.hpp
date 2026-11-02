// Local filter: every whitespace-separated term must match literally or by pinyin.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace tui {
struct Match {
    uint32_t score = 0;
    std::vector<std::pair<size_t, size_t>> ranges;  // Code point offsets, half open and merged.
};
std::optional<Match> match(std::string_view query, std::string_view text);
// Lower-case pinyin syllable of one Han character, or empty when it is not in the table.
// The index and the keys tool's stronger filter must use the same table.
std::string_view pinyin_syllable(char32_t ch);
}  // namespace tui
