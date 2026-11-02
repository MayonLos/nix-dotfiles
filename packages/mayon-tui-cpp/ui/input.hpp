// Single-line editor with code point cursor and the shared readline-style keys.
#pragma once
#include <string>
#include <string_view>

#include "ui/keys.hpp"

namespace tui {
class TextInput {
public:
    // Same limit as the Rust TextInput; paste stops at the limit instead of dropping everything.
    static constexpr size_t kMaxChars = 4096;
    void set(std::string_view text);
    void clear() { text_.clear(); cursor_ = 0; }
    bool empty() const { return text_.empty(); }
    std::string str() const;
    std::string before_cursor() const;
    void paste(std::string_view text);
    // True when the text changed.
    bool handle(const Key& key);

private:
    std::u32string text_;
    size_t cursor_ = 0;
};
}  // namespace tui
