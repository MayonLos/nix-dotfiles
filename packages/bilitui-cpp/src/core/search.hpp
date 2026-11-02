// Local filter: every whitespace-separated term must match literally or by pinyin.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace bili {
struct Match {
    uint32_t score = 0;
    std::vector<std::pair<size_t, size_t>> ranges;  // Code point offsets, half open and merged.
};
std::optional<Match> match(std::string_view query, std::string_view text);
}  // namespace bili
