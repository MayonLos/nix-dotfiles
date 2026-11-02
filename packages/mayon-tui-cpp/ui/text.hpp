// UTF-8, terminal-safe text and small formatting helpers.
#pragma once
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace tui {
std::u32string decode(std::string_view text);
std::string encode(std::u32string_view text);
void append(std::string& out, char32_t ch);
// Removes markup and every control character except '\n', so remote text cannot drive the terminal.
std::string clean(std::string_view text);
std::string count(uint64_t value);
std::string normalize_duration(std::string_view text);
std::string seconds_text(uint64_t seconds);
std::string date_text(uint64_t epoch);
std::string form_encode(std::string_view value);
std::string trim(std::string_view value);
std::vector<std::string> split_words(std::string_view value);
}  // namespace tui
