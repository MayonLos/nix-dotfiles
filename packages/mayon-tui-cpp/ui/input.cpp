#include "ui/input.hpp"

#include "ui/text.hpp"

namespace tui {
void TextInput::set(std::string_view text) {
    text_ = decode(text);
    cursor_ = text_.size();
}
std::string TextInput::str() const { return encode(text_); }
std::string TextInput::before_cursor() const { return encode(std::u32string_view(text_).substr(0, cursor_)); }
void TextInput::paste(std::string_view text) {
    std::u32string flat;
    for (const char32_t ch : decode(text)) {
        if (ch == U'\n' || ch == U'\r' || ch == U'\t') flat.push_back(U' ');
        else if (ch >= 0x20 && ch != 0x7F && !(ch >= 0x80 && ch < 0xA0)) flat.push_back(ch);
    }
    if (text_.size() + flat.size() > 512) return;
    text_.insert(cursor_, flat);
    cursor_ += flat.size();
}
bool TextInput::handle(const Key& key) {
    const auto word_start = [&] {
        size_t at = cursor_;
        while (at > 0 && text_[at - 1] == U' ') --at;
        while (at > 0 && text_[at - 1] != U' ') --at;
        return at;
    };
    if (key.code == KeyCode::Left) { if (cursor_ > 0) --cursor_; return false; }
    if (key.code == KeyCode::Right) { if (cursor_ < text_.size()) ++cursor_; return false; }
    if (key.code == KeyCode::Home || (key.ctrl && key.ch == U'a')) { cursor_ = 0; return false; }
    if (key.code == KeyCode::End || (key.ctrl && key.ch == U'e')) { cursor_ = text_.size(); return false; }
    if (key.code == KeyCode::Backspace) {
        if (cursor_ == 0) return false;
        const size_t from = key.alt ? word_start() : cursor_ - 1;
        text_.erase(from, cursor_ - from);
        cursor_ = from;
        return true;
    }
    if (key.code == KeyCode::Delete) {
        if (cursor_ >= text_.size()) return false;
        text_.erase(cursor_, 1);
        return true;
    }
    if (key.ctrl && key.ch == U'u') { text_.erase(0, cursor_); cursor_ = 0; return true; }
    if (key.ctrl && key.ch == U'k') { text_.erase(cursor_); return true; }
    if (key.ctrl && key.ch == U'w') {
        const size_t from = word_start();
        text_.erase(from, cursor_ - from);
        cursor_ = from;
        return true;
    }
    if (key.code == KeyCode::Char && !key.ctrl && !key.alt && key.ch >= 0x20 && text_.size() < 512) {
        text_.insert(cursor_, 1, key.ch);
        ++cursor_;
        return true;
    }
    return false;
}
}  // namespace tui
